
#include <perfMon/dag_statDrv.h>
#include <perfMon/dag_perfTimer.h>
#include <ioSys/dag_dataBlock.h>
#include <math/dag_TMatrix.h>
#include "render.h"
#include <AvailabilityMacros.h>
#include <osApiWrappers/dag_direct.h>
#include <osApiWrappers/dag_files.h>
#include <thread>

namespace drv3d_metal
{
  static const uint32_t PRECACHE_VERSION = _MAKE4C('1.9');

  std::thread g_saver;
  std::thread g_compiler;

  static MTLRenderPipelineDescriptor* buildPipelineDescriptor(id<MTLFunction> vshader, id<MTLFunction> pshader,
                                      MTLVertexDescriptor* vertexDescriptor, const Program::RenderState& rstate, bool discard)
  {
    MTLRenderPipelineDescriptor* pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];

#if DAGOR_DBGLEVEL > 0
    pipelineStateDescriptor.label = [NSString stringWithFormat:@"%@@%@%@%@", vshader.label, pshader ? pshader.label : @"",
                                     discard ? @"_discard" : @"", rstate.raster_state.ablend ? @"_blend" : @""];
#endif
    pipelineStateDescriptor.sampleCount = rstate.sample_count;

    pipelineStateDescriptor.vertexFunction = vshader;
    pipelineStateDescriptor.fragmentFunction =  pshader;
    pipelineStateDescriptor.vertexDescriptor = vertexDescriptor;

    if (rstate.is_volume)
      pipelineStateDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassTriangle;
    else
      pipelineStateDescriptor.inputPrimitiveTopology = MTLPrimitiveTopologyClassUnspecified;

    pipelineStateDescriptor.depthAttachmentPixelFormat = rstate.depthFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = rstate.stencilFormat;
    pipelineStateDescriptor.alphaToCoverageEnabled = rstate.raster_state.a2c;

    int writeMask = rstate.raster_state.writeMask;
    bool hasColor = false;

    for (int i = 0; i < Program::MAX_SIMRT; i++, writeMask>>=4)
    {
      pipelineStateDescriptor.colorAttachments[i].pixelFormat = rstate.pixelFormat[i];
      hasColor |= rstate.pixelFormat[i] != MTLPixelFormatInvalid;

      int metal_mask = 0;
      int mask = writeMask & 0xF;

      metal_mask |= MTLColorWriteMaskRed * ((mask&WRITEMASK_RED0) > 0);
      metal_mask |= MTLColorWriteMaskBlue * ((mask&WRITEMASK_BLUE0) > 0);
      metal_mask |= MTLColorWriteMaskGreen * ((mask&WRITEMASK_GREEN0) > 0);
      metal_mask |= MTLColorWriteMaskAlpha * ((mask&WRITEMASK_ALPHA0) > 0);

      pipelineStateDescriptor.colorAttachments[i].writeMask = metal_mask;

      MTLRenderPipelineColorAttachmentDescriptor *renderbufferAttachment = pipelineStateDescriptor.colorAttachments[i];
      if (rstate.raster_state.ablend && rstate.pixelFormat[i] != 0)
      {
        renderbufferAttachment.blendingEnabled = true;

        renderbufferAttachment.alphaBlendOperation = rstate.raster_state.sepblend ?
                (MTLBlendOperation)rstate.raster_state.ablendOp : (MTLBlendOperation)rstate.raster_state.rgbblendOp;
        renderbufferAttachment.rgbBlendOperation = (MTLBlendOperation)rstate.raster_state.rgbblendOp;

        renderbufferAttachment.sourceAlphaBlendFactor = rstate.raster_state.sepblend ?
                (MTLBlendFactor)rstate.raster_state.ablendScr : (MTLBlendFactor)rstate.raster_state.rgbblendScr;
        renderbufferAttachment.sourceRGBBlendFactor = (MTLBlendFactor)rstate.raster_state.rgbblendScr;

        renderbufferAttachment.destinationAlphaBlendFactor = rstate.raster_state.sepblend ?
                (MTLBlendFactor)rstate.raster_state.ablendDst : (MTLBlendFactor)rstate.raster_state.rgbblendDst;
        renderbufferAttachment.destinationRGBBlendFactor = (MTLBlendFactor)rstate.raster_state.rgbblendDst;
      }
      else
      {
        renderbufferAttachment.blendingEnabled = false;
      }
    }

    return pipelineStateDescriptor;
  }

  static uint64_t buildRenderStateHash(const Program::RenderState& rstate)
  {
    uint64_t hash = 0;
    hash_combine(hash, rstate.raster_state.state);

    for (int i = 0; i < Program::MAX_SIMRT; i++)
      hash_combine(hash, std::hash<uint32_t>{}(rstate.pixelFormat[i]));
    hash_combine(hash, std::hash<uint32_t>{}(rstate.depthFormat));
    hash_combine(hash, std::hash<uint32_t>{}(rstate.stencilFormat));

    for (int i = 0; i < BUFFER_POINT_COUNT; i++)
      hash_combine(hash, std::hash<uint32_t>{}(rstate.vbuffer_stride[i]));
    hash_combine(hash, std::hash<uint32_t>{}(rstate.sample_count));
    hash_combine(hash, std::hash<uint32_t>{}(rstate.is_volume));

    return hash;
  }

  void ShadersPreCache::saverThread()
  {
    while (g_is_exiting == false)
    {
      ska::flat_hash_map<uint64_t, ShadersPreCache::CachedShader*> shaderCache;
      ska::flat_hash_map<uint64_t, ShadersPreCache::CachedVertexDescriptor*> descriptorCache;
      ska::flat_hash_map<uint64_t, ShadersPreCache::CachedPipelineState*> psoCache;
      ska::flat_hash_map<uint64_t, ShadersPreCache::CachedComputePipelineState*> csoCache;
      eastl::vector<QueuedShader> queued_shaders;
      {
        std::unique_lock<std::mutex> l(g_saver_mutex);
        g_saver_condition.wait(l);

        shaderCache = render.shadersPreCache.shader_cache;
        descriptorCache = render.shadersPreCache.descriptor_cache;
        psoCache = render.shadersPreCache.pso_cache;
        csoCache = render.shadersPreCache.cso_cache;
        queued_shaders = eastl::move(g_queued_shaders);
      }
      if (shaderCache.size() != g_shaders_saved)
        render.shadersPreCache.saveShaders(shaderCache);
      if (descriptorCache.size() != g_descriptors_saved)
        render.shadersPreCache.saveDescriptors(descriptorCache);
      if (psoCache.size() != g_psos_saved)
        render.shadersPreCache.savePSOs(psoCache);
      if (csoCache.size() != g_csos_saved)
        render.shadersPreCache.saveCSOs(csoCache);
      for (auto & shd : queued_shaders)
      {
        char curShdCachePath[1024];
        snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/%llu.cache", render.shadersPreCache.shdCachePath, shd.hash);

        FILE* fl = fopen(curShdCachePath, "wb");
        if (fl)
        {
          fwrite(shd.entry, 96, 1, fl);
          fwrite(shd.data.data(), (uint32_t)shd.data.size(), 1, fl);
          fclose(fl);
        }
        else
        {
          debug("ShadersPreCache: %llu was not saved", shd.hash);
        }
      }

      g_shaders_saved = shaderCache.size();
      g_descriptors_saved = descriptorCache.size();
      g_psos_saved = psoCache.size();
      g_csos_saved = csoCache.size();
    }
    g_saver_exited = true;
  }

  ShadersPreCache::ShadersPreCache()
    : shader_cache_objects(sizeof(CachedShader), 256)
    , descriptor_cache_objects(sizeof(CachedVertexDescriptor), 32)
    , pso_cache_objects(sizeof(CachedPipelineState), 256)
    , cso_cache_objects(sizeof(CachedComputePipelineState), 256)
  {
    shdCachePath[0] = 0;
  }

  void ShadersPreCache::init(uint32_t version)
  {
    g_is_exiting = false;
    g_saver_exited = false;
    g_compiler_exited = false;

    cache_version = version ? version : PRECACHE_VERSION;

    #if _TARGET_PC_MACOSX
    NSString *dir = [[NSBundle mainBundle] bundlePath];

    HashMD5 hash;
    hash.calc([dir UTF8String], [dir length]);

    snprintf(shdCachePath, sizeof(shdCachePath), "%s/cache/%u/%s", getenv("HOME"), cache_version, hash.get());
    #else
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *dir = [paths objectAtIndex:0];
    snprintf(shdCachePath, sizeof(shdCachePath), "%s/%u", [dir UTF8String], cache_version);
    #endif

    dd_mkdir(shdCachePath);

    bool async_pso_cache_loading = dgs_get_settings()->getBlockByNameEx("graphics")->getBool("asyncLoadPSOCache", false);
    pso_cache_loaded = false;

    if (!async_pso_cache_loading)
      loadPreCache();

    g_saver = std::thread([]()
    {
      render.shadersPreCache.saverThread();
    });
    g_compiler = std::thread([]()
    {
      render.shadersPreCache.compilerThread();
    });
  }

  void ShadersPreCache::loadPreCache()
  {
    if (pso_cache_loaded)
      return;

    debug("[METAL] PSO cache");

    int64_t time = profile_ref_ticks();

    const char* root = shdCachePath;
    // shader map
    {
      char curShdCachePath[1024];
      snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/shaders.cache", root);

      file_ptr_t fl = df_open(curShdCachePath, DF_READ|DF_IGNORE_MISSING);
      if (fl)
      {
        uint32_t count = 0;
        df_read(fl, &count, sizeof(count));
        for (uint32_t i = 0; i < count; ++i)
        {
          QueuedShader shd;
          df_read(fl, &shd.hash, sizeof(shd.hash));

          snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/%llu.cache", root, shd.hash);

          file_ptr_t fl_shd = df_open(curShdCachePath, DF_READ|DF_IGNORE_MISSING);
          if (fl_shd)
          {
            int sz_shd = df_length(fl_shd);

            shd.data.resize(sz_shd - sizeof(shd.entry));
            df_read(fl_shd, shd.entry, sizeof(shd.entry));
            df_read(fl_shd, shd.data.data(), shd.data.size());
            df_close(fl_shd);

            @autoreleasepool
            {
              compileShader(shd);
            }
          }
        }
        df_close(fl);

        debug("ShadersPreCache: shaders.cache was loaded with %i shaders in list", (int)shader_cache.size());
        g_shaders_saved = shader_cache.size();
      }
      else
      {
        debug("ShadersPreCache: shaders.cache was not loaded");
      }
    }
    // vertex descriptors
    {
      char curShdCachePath[1024];
      snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/descriptors.cache", root);

      file_ptr_t fl = df_open(curShdCachePath, DF_READ|DF_IGNORE_MISSING);
      if (fl)
      {
        uint32_t count = 0;
        df_read(fl, &count, sizeof(count));

        CachedVertexDescriptor desc;
        for (uint32_t i = 0; i < count; ++i)
        {
          uint64_t hash = 0;
          df_read(fl, &hash, sizeof(hash));

          df_read(fl, &desc.attr_count, sizeof(desc.attr_count));
          df_read(fl, &desc.stream_count, sizeof(desc.stream_count));
          df_read(fl, &desc.attributes, sizeof(desc.attributes));
          df_read(fl, &desc.streams, sizeof(desc.streams));

          compileDescriptor(hash, desc);
        }
        df_close(fl);

        debug("ShadersPreCache: descriptors.cache was loaded with %i shaders in list", (int)descriptor_cache.size());
        g_descriptors_saved = descriptor_cache.size();
      }
      else
      {
        debug("ShadersPreCache: descriptors.cache was not loaded");
      }
    }
    // pipelines
    {
      char curShdCachePath[1024];
      snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/pipelines.cache", root);

      file_ptr_t fl = df_open(curShdCachePath, DF_READ|DF_IGNORE_MISSING);
      if (fl)
      {
        uint32_t count = 0;
        df_read(fl, &count, sizeof(count));
        for (uint32_t i = 0; i < count; ++i)
        {
          uint64_t hash = 0, vs_hash = 0, ps_hash = 0, decl_hash = 0;
          df_read(fl, &hash, sizeof(hash));
          df_read(fl, &vs_hash, sizeof(vs_hash));
          df_read(fl, &ps_hash, sizeof(ps_hash));
          df_read(fl, &decl_hash, sizeof(decl_hash));

          Program::RenderState rstate;
          df_read(fl, &rstate, sizeof(rstate));

          uint32_t discard = 0;
          df_read(fl, &discard, sizeof(discard));

          CachedPipelineState* pso = (CachedPipelineState*)pso_cache_objects.allocateOneBlock();
          pso->vs_hash = vs_hash;
          pso->ps_hash = ps_hash;
          pso->descriptor_hash = decl_hash;
          pso->rstate = rstate;
          pso->pso = nil;
          pso->discard = discard;

          compilePipeline(hash, pso, true);
        }
        df_close(fl);

        debug("ShadersPreCache: pipelines.cache was loaded with %i shaders in list", (int)pso_cache.size());
        g_psos_saved = pso_cache.size();
      }
      else
      {
        debug("ShadersPreCache: pipelines.cache was not loaded");
      }
    }
    // cs pipelines
    {
      char curShdCachePath[1024];
      snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/cs_pipelines.cache", root);

      file_ptr_t fl = df_open(curShdCachePath, DF_READ|DF_IGNORE_MISSING);
      if (fl)
      {
        uint32_t count = 0;
        df_read(fl, &count, sizeof(count));
        for (uint32_t i = 0; i < count; ++i)
        {
          uint64_t hash = 0;
          df_read(fl, &hash, sizeof(hash));

          compilePipeline(hash);
        }
        df_close(fl);

        debug("ShadersPreCache: cs_pipelines.cache was loaded with %i shaders in list", (int)cso_cache.size());
        g_csos_saved = cso_cache.size();
      }
      else
      {
        debug("ShadersPreCache: cs_pipelines.cache was not loaded");
      }
    }

    time = profile_time_usec(time);

    debug("[METAL] PSO cache loading took %.3fs", time / 1000000.f);

    pso_cache_loaded = true;
    g_cache_dirty = true;
  }

  void ShadersPreCache::saveShaders(const ska::flat_hash_map<uint64_t, CachedShader*>& shaderCache)
  {
    char curShdCachePath[1024];
    snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/shaders.cache", shdCachePath);

    FILE* fl = fopen(curShdCachePath, "wb");
    if (fl)
    {
      uint32_t count = (uint32_t)shaderCache.size();
      fwrite(&count, sizeof(count), 1, fl);
      for (auto & it : shaderCache)
        fwrite(&it.first, sizeof(it.first), 1, fl);
      fclose(fl);

      debug("ShadersPreCache: shaders.cache was saved with %i shaders in list", count);
    }
    else
    {
      debug("ShadersPreCache: shaders.cache was not saved");
    }
  }

  void ShadersPreCache::saveDescriptors(const ska::flat_hash_map<uint64_t, CachedVertexDescriptor*>& descriptorCache)
  {
    char curShdCachePath[1024];
    snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/descriptors.cache", shdCachePath);

    FILE* fl = fopen(curShdCachePath, "wb");
    if (fl)
    {
      uint32_t count = (uint32_t)descriptorCache.size();
      fwrite(&count, sizeof(count), 1, fl);
      for (auto & it : descriptorCache)
      {
        fwrite(&it.first, sizeof(it.first), 1, fl);
        fwrite(&it.second->attr_count, sizeof(it.second->attr_count), 1, fl);
        fwrite(&it.second->stream_count, sizeof(it.second->stream_count), 1, fl);
        fwrite(&it.second->attributes, sizeof(it.second->attributes), 1, fl);
        fwrite(&it.second->streams, sizeof(it.second->streams), 1, fl);
      }
      fclose(fl);

      debug("ShadersPreCache: descriptors.cache was saved with %i shaders in list", count);
    }
    else
    {
      debug("ShadersPreCache: descriptors.cache was not saved");
    }
  }

  void ShadersPreCache::savePSOs(const ska::flat_hash_map<uint64_t, CachedPipelineState*>& psoCache)
  {
    char curShdCachePath[1024];
    snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/pipelines.cache", shdCachePath);

    FILE* fl = fopen(curShdCachePath, "wb");
    if (fl)
    {
      uint32_t count = (uint32_t)psoCache.size();
      fwrite(&count, sizeof(count), 1, fl);
      for (auto & it : psoCache)
      {
        fwrite(&it.first, sizeof(it.first), 1, fl);
        fwrite(&it.second->vs_hash, sizeof(it.second->vs_hash), 1, fl);
        fwrite(&it.second->ps_hash, sizeof(it.second->ps_hash), 1, fl);
        fwrite(&it.second->descriptor_hash, sizeof(it.second->descriptor_hash), 1, fl);
        fwrite(&it.second->rstate, sizeof(it.second->rstate), 1, fl);
        fwrite(&it.second->discard, sizeof(it.second->discard), 1, fl);
      }
      fclose(fl);

      debug("ShadersPreCache: pipelines.cache was saved with %i shaders in list", count);
    }
    else
    {
      debug("ShadersPreCache: pipelines.cache was not saved");
    }
  }

  void ShadersPreCache::saveCSOs(const ska::flat_hash_map<uint64_t, CachedComputePipelineState*>& csoCache)
  {
    char curShdCachePath[1024];
    snprintf(curShdCachePath, sizeof(curShdCachePath), "%s/cs_pipelines.cache", shdCachePath);

    FILE* fl = fopen(curShdCachePath, "wb");
    if (fl)
    {
      uint32_t count = (uint32_t)csoCache.size();
      fwrite(&count, sizeof(count), 1, fl);
      for (auto & it : csoCache)
      {
        fwrite(&it.first, sizeof(it.first), 1, fl);
      }
      fclose(fl);

      debug("ShadersPreCache: cs_pipelines.cache was saved with %i shaders in list", count);
    }
    else
    {
      debug("ShadersPreCache: cs_pipelines.cache was not saved");
    }
  }

  void ShadersPreCache::savePreCache()
  {
    saveShaders(shader_cache);
    saveDescriptors(descriptor_cache);
    savePSOs(pso_cache);
    saveCSOs(cso_cache);
  }

  void ShadersPreCache::tickCache()
  {
    {
      std::unique_lock<std::mutex> l_saver(g_saver_mutex);
      std::unique_lock<std::mutex> l_compiler(g_compiler_mutex);
      for (auto & pso : pso_compiler_done)
      {
        if (pso.second->pso)
        {
          pso_cache[pso.first] = pso.second;
          g_cache_dirty = true;
        }
        else
          pso_cache_objects.freeOneBlock(pso.second->pso);
      }
      for (auto & sh : shader_compiler_done)
      {
        if (sh.second->func)
        {
          shader_cache[sh.first] = sh.second;
          g_cache_dirty = true;
        }
        else
          shader_cache_objects.freeOneBlock(sh.second);
      }
      render.async_pso_compilation_length = (uint32_t)(pso_compiler_cache.size() + shader_compiler_cache.size());
    }

    if (g_cache_dirty == false || pso_cache_loaded == false)
      return;

    std::unique_lock<std::mutex> l(g_saver_mutex);
    g_saver_condition.notify_all();

    g_cache_dirty = false;
  }

  id <MTLFunction> ShadersPreCache::compileShader(const QueuedShader& shader)
  {
    TIME_PROFILE(compile_shader);

    id <MTLFunction> func = nil;
    id <MTLLibrary> lib = nil;

    NSError* err = nil;
    if (shader.data.size() > 4 && memcmp(shader.data.data(), "MTLB", 4) == 0)
    {
      dispatch_data_t buffer = dispatch_data_create(shader.data.data(), shader.data.size(), nil, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
      lib = [drv3d_metal::render.device newLibraryWithData:buffer error:&err];
      dispatch_release(buffer);
    }
    else
    {
      MTLCompileOptions* options = [[MTLCompileOptions alloc] init];
      if (@available(iOS 15, macOS 12.0, *))
      {
        // Really important! Only 2.4 supports ray queries for raytracing!
        // And spirv-cross can emit raytracing code only with queries.
        // That means that raytracing shaders are available only for macOS 12+.
        options.languageVersion = MTLLanguageVersion2_4;
        options.preserveInvariance = YES;
      }
      else if (@available(iOS 14, macOS 11.0, *))
      {
        options.languageVersion = MTLLanguageVersion2_3;
        options.preserveInvariance = YES;
      }
      else if (@available(macOS 10.15, *))
      {
        options.languageVersion = MTLLanguageVersion2_2;
      }
      NSString* sh_src = [NSString stringWithUTF8String:(const char*)shader.data.data()];
      lib = [drv3d_metal::render.device newLibraryWithSource : sh_src options : options error : &err];
      [options release];
    }
    [lib retain];

    if (lib)
    {
      if ([[lib functionNames] count] > 0)
      {
        func = [lib newFunctionWithName : [[lib functionNames] objectAtIndex:0]];
        [func retain];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200 && DAGOR_DBGLEVEL > 0
        func.label = [[NSString alloc] initWithBytes:shader.entry length : strlen(shader.entry) encoding : NSUTF8StringEncoding];
#endif
      }
      else
      {
        logerr("Error, shader not contain function, error %s", [[err localizedDescription] UTF8String]);
        return nil;
      }
    }
    else
    {
      logerr("Failed to compile shader, error %s", [[err localizedDescription] UTF8String]);
      return nil;
    }

    if (shader.result == nullptr)
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);

      CachedShader* cache = (CachedShader*)shader_cache_objects.allocateOneBlock();
      cache->func = func;
      cache->lib = lib;
      shader_cache[shader.hash] = cache;
    }
    else
    {
      shader.result->func = func;
      shader.result->lib = lib;
    }

    return func;
  }

  id <MTLFunction> ShadersPreCache::getShader(uint64_t shader_hash, const char* entry, const char* shader_data, int shader_size, bool async)
  {
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);

      auto it = shader_cache.find(shader_hash);
      if (it != end(shader_cache))
        return it->second->func;
    }

    QueuedShader shd;
    shd.hash = shader_hash;
    memcpy(shd.entry, entry, 96);
    shd.data.insert(shd.data.end(), shader_data, shader_data + shader_size);

    {
      std::unique_lock<std::mutex> l(g_saver_mutex);
      g_queued_shaders.push_back(shd);
    }

    if (async)
    {
      std::unique_lock<std::mutex> l_compiler(g_compiler_mutex);
      if (shader_compiler_cache.find(shader_hash) == shader_compiler_cache.end())
      {
        std::unique_lock<std::mutex> l_saver(g_saver_mutex);
        shd.result = (CachedShader*)shader_cache_objects.allocateOneBlock();
        shd.result->func = nil;
        shd.result->lib = nil;
        shader_compiler_cache[shader_hash] = shd;

        g_compiler_condition.notify_all();
      }
      return nil;
    }
    else
    {
      g_cache_dirty = true;
      return compileShader(shd);
    }
  }

  MTLVertexDescriptor* ShadersPreCache::compileDescriptor(uint64_t hash, CachedVertexDescriptor& desc)
  {
    desc.descriptor = [[MTLVertexDescriptor vertexDescriptor] retain];
    for (uint32_t i = 0 ; i < desc.attr_count; ++i)
    {
      int reg = desc.attributes[i].slot;
      desc.descriptor.attributes[reg].format = (MTLVertexFormat)desc.attributes[i].format;
      desc.descriptor.attributes[reg].bufferIndex = desc.attributes[i].stream;
      desc.descriptor.attributes[reg].offset = desc.attributes[i].offset;
    }
    for (uint32_t i = 0 ; i < desc.stream_count; ++i)
    {
      int reg = desc.streams[i].stream;
      desc.descriptor.layouts[reg].stride = desc.streams[i].stride;
      desc.descriptor.layouts[reg].stepFunction = (MTLVertexStepFunction)desc.streams[i].step;
      G_ASSERT(desc.streams[i].stride);
    }

    CachedVertexDescriptor* d = (CachedVertexDescriptor*)descriptor_cache_objects.allocateOneBlock();
    *d = desc;
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);
      descriptor_cache[hash] = d;
    }

    return desc.descriptor;
  }

  MTLVertexDescriptor* ShadersPreCache::buildDescriptor(Shader* vshader, VDecl* vdecl, const Program::RenderState& rstate, uint64_t& hash)
  {
    G_ASSERT(vshader);
    G_ASSERT(vdecl);
    CachedVertexDescriptor desc;

    hash = 0;

    uint32_t buffer_mask = 0;
    for (int i = 0; i < vshader->num_va; i++)
    {
      Shader::VA& va = vshader->va[i];

      int location = 0;
      for (int l = 0; l<vdecl->num_location; l++)
      {
        if (vdecl->locations[l].vsdr == va.vsdr)
        {
          location = l;
          break;
        }
      }

      CachedVertexDescriptor::Attr& attr = desc.attributes[desc.attr_count++];
      attr.format = vdecl->vertexDescriptor.attributes[location].format;
      attr.stream = vdecl->vertexDescriptor.attributes[location].bufferIndex;
      attr.offset = vdecl->vertexDescriptor.attributes[location].offset;
      attr.slot = va.reg;

      G_ASSERT(vdecl->vertexDescriptor.attributes[location].bufferIndex < 256);
      G_ASSERT(vdecl->vertexDescriptor.attributes[location].offset < 256);
      G_ASSERT(attr.slot < CachedVertexDescriptor::max_attributes);
      G_ASSERT(attr.stream < CachedVertexDescriptor::max_streams);

      hash_combine(hash, std::hash<uint32_t>{}(attr.format));
      hash_combine(hash, std::hash<uint8_t>{}(attr.stream));
      hash_combine(hash, std::hash<uint8_t>{}(attr.offset));
      hash_combine(hash, std::hash<uint8_t>{}(attr.slot));

      buffer_mask |= 1 << vdecl->vertexDescriptor.attributes[location].bufferIndex;
    }

    G_ASSERT(vdecl->num_streams < CachedVertexDescriptor::max_streams);
    for (int i = 0; i < vdecl->num_streams; i++)
    {
      if (!(buffer_mask & (1 << i)))
        continue;
      CachedVertexDescriptor::Stream& stream = desc.streams[desc.stream_count++];
      stream.stream = i;
      stream.stride = rstate.vbuffer_stride[i];
      stream.step = vdecl->vertexDescriptor.layouts[i].stepFunction;

      G_ASSERT(stream.stride);

      hash_combine(hash, std::hash<uint8_t>{}(stream.stream));
      hash_combine(hash, std::hash<uint8_t>{}(stream.stride));
      hash_combine(hash, std::hash<uint8_t>{}(stream.step));
    }

    auto it = descriptor_cache.find(hash);
    if (it != end(descriptor_cache))
      return it->second->descriptor;

    return compileDescriptor(hash, desc);
  }

  id <MTLRenderPipelineState> ShadersPreCache::compilePipeline(uint64_t hash, CachedPipelineState* pso, bool free)
  {
    TIME_PROFILE(compile_pipeline);

    if (!free)
      g_saver_mutex.lock();

    auto vs_it = shader_cache.find(pso->vs_hash);
    auto ps_it = shader_cache.find(pso->ps_hash);
    id<MTLFunction> vs = vs_it == end(shader_cache) ? nil : vs_it->second->func;
    id<MTLFunction> ps = ps_it == end(shader_cache) ? nil : ps_it->second->func;
    if (vs == nil)
    {
      logwarn("Failed to find vs when creating pso");
      if (free)
        pso_cache_objects.freeOneBlock(pso);
      else
        g_saver_mutex.unlock();
      return nullptr;
    }

    auto desc_it = descriptor_cache.find(pso->descriptor_hash);
    MTLVertexDescriptor* desc = desc_it == end(descriptor_cache) ? nil : desc_it->second->descriptor;

    if (!free)
      g_saver_mutex.unlock();

    MTLRenderPipelineDescriptor* pipelineStateDescriptor = buildPipelineDescriptor(vs, ps, desc, pso->rstate, pso->discard);

    NSError *error = nil;
    id <MTLRenderPipelineState> pipelineState = [render.device newRenderPipelineStateWithDescriptor : pipelineStateDescriptor
                                                 error : &error];
    if (!pipelineState)
    {
      logerr("Failed to created pipeline state, error %s",
            [[error localizedDescription] UTF8String]);
      if (free)
        pso_cache_objects.freeOneBlock(pso);
      return nullptr;
    }

    pso->pso = pipelineState;
    if (free)
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);
      pso_cache[hash] = pso;
    }

    [pipelineStateDescriptor release];

    return pipelineState;
  }

  id <MTLRenderPipelineState> ShadersPreCache::getState(Program* program, VDecl* vdecl, const Program::RenderState& rstate, bool async)
  {
    G_ASSERT(program);
    vdecl = vdecl ? vdecl : program->vdecl;

    Shader* vshader = program->vshader;
    Shader* pshader = program->pshader;
    G_ASSERT(vshader);

    uint64_t hash = 0;
    uint64_t decl_hash = vshader->num_va > 0 ? vdecl->hash : 0;
    uint64_t vs_hash = vshader->shader_hash;
    uint64_t ps_hash = pshader ? pshader->shader_hash : 0;
    uint64_t rstate_hash = buildRenderStateHash(rstate);

    hash_combine(hash, decl_hash);
    hash_combine(hash, vs_hash);
    hash_combine(hash, ps_hash);
    hash_combine(hash, rstate_hash);

    auto it = pso_cache.find(hash);
    if (it != end(pso_cache))
      return it->second->pso;

    MTLVertexDescriptor* vertexDescriptor = nil;
    if (vshader->num_va > 0)
      vertexDescriptor = buildDescriptor(vshader, vdecl, rstate, decl_hash);
    else
      decl_hash = 0;

    CachedPipelineState* pso = (CachedPipelineState*)pso_cache_objects.allocateOneBlock();
    pso->vs_hash = vs_hash;
    pso->ps_hash = ps_hash;
    pso->descriptor_hash = decl_hash;
    pso->rstate = rstate;
    pso->pso = nil;
    pso->discard = pshader && pshader->src ? !!strstr([pshader->src UTF8String], "discard_fragment") : false;

    if (async)
    {
      std::unique_lock<std::mutex> l(g_compiler_mutex);
      if (pso_compiler_cache.find(hash) == pso_compiler_cache.end())
      {
        pso_compiler_cache[hash] = pso;
        g_compiler_condition.notify_all();
      }
      return nil;
    }
    else
    {
      id <MTLRenderPipelineState> ret = compilePipeline(hash, pso, true);
      if (ret != nil)
        g_cache_dirty = true;

      return ret;
    }
  }

  id <MTLComputePipelineState> ShadersPreCache::compilePipeline(uint64_t hash)
  {
    auto it = cso_cache.find(hash);
    if (it != end(cso_cache))
      return it->second->cso;

    auto cs_it = shader_cache.find(hash);
    if (cs_it == shader_cache.end())
    {
      logerr("Failed to find shader for compute pipeline");
      return nullptr;
    }

    NSError *error = nil;
    id<MTLComputePipelineState> csPipeline = [render.device newComputePipelineStateWithFunction : cs_it->second->func error : &error];
    if (!csPipeline)
    {
      logerr("Failed to created cs pipeline state, error %s", [[error localizedDescription] UTF8String]);
      return nullptr;
    }

    CachedComputePipelineState* cso = (CachedComputePipelineState*)cso_cache_objects.allocateOneBlock();
    cso->cso = csPipeline;
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);
      cso_cache[hash] = cso;
      g_cache_dirty = true;
    }

    return csPipeline;
  }

  void ShadersPreCache::compilerThread()
  {
    TIME_PROFILE_THREAD("shader_compiler");

    uint64_t work_hash = 0;
    CachedPipelineState* work_pso = nullptr;

    uint64_t shader_hash = 0;
    QueuedShader shader;
    while (g_is_exiting == false)
    {
      {
        std::unique_lock<std::mutex> l(g_compiler_mutex);
        if (work_hash)
        {
          G_ASSERT(work_pso);
          pso_compiler_done[work_hash] = work_pso;
        }
        if (shader_hash)
        {
          G_ASSERT(shader.result);
          shader_compiler_done[shader_hash] = shader.result;
        }

        if (shader_compiler_cache.empty() && pso_compiler_cache.empty())
          g_compiler_condition.wait(l);

        if (!shader_compiler_cache.empty())
        {
          auto it = shader_compiler_cache.begin();
          shader_hash = it->first;
          shader = eastl::move(it->second);
          shader_compiler_cache.erase(it);
        }
        else
          shader_hash = 0;

        if (!pso_compiler_cache.empty() && shader_hash == 0)
        {
          auto it = pso_compiler_cache.begin();
          work_hash = it->first;
          work_pso = it->second;
          pso_compiler_cache.erase(it);
        }
        else
          work_hash = 0;
      }

      if (shader_hash)
        compileShader(shader);
      if (work_hash)
        compilePipeline(work_hash, work_pso, false);
    }
    g_compiler_exited = true;
  }

  void ShadersPreCache::release()
  {
    for (auto & it : shader_cache)
    {
      if (it.second->func)
        [it.second->func release];
      if (it.second->lib)
        [it.second->lib release];
    }

    g_is_exiting = true;
    {
      std::unique_lock<std::mutex> l(g_saver_mutex);
      g_saver_condition.notify_all();
    }
    {
      std::unique_lock<std::mutex> l(g_compiler_mutex);
      g_compiler_condition.notify_all();
    }

    while (g_saver_exited == false || g_compiler_exited == false)
        ;

    g_saver.join();
    g_compiler.join();

    savePreCache();
  }
}
