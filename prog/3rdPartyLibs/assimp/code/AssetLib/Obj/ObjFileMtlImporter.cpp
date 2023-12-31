/*
---------------------------------------------------------------------------
Open Asset Import Library (assimp)
---------------------------------------------------------------------------

Copyright (c) 2006-2020, assimp team

All rights reserved.

Redistribution and use of this software in source and binary forms,
with or without modification, are permitted provided that the following
conditions are met:

* Redistributions of source code must retain the above
  copyright notice, this list of conditions and the
  following disclaimer.

* Redistributions in binary form must reproduce the above
  copyright notice, this list of conditions and the
  following disclaimer in the documentation and/or other
  materials provided with the distribution.

* Neither the name of the assimp team, nor the names of its
  contributors may be used to endorse or promote products
  derived from this software without specific prior
  written permission of the assimp team.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
---------------------------------------------------------------------------
*/

#ifndef ASSIMP_BUILD_NO_OBJ_IMPORTER

#include "ObjFileMtlImporter.h"
#include "ObjFileData.h"
#include "ObjTools.h"
#include <assimp/ParsingUtils.h>
#include <assimp/fast_atof.h>
#include <assimp/material.h>
#include <stdlib.h>
#include <assimp/DefaultLogger.hpp>

namespace Assimp {

// Material specific token (case insensitive compare)
static const eastl::string DiffuseTexture = "map_Kd";
static const eastl::string AmbientTexture = "map_Ka";
static const eastl::string SpecularTexture = "map_Ks";
static const eastl::string OpacityTexture = "map_d";
static const eastl::string EmissiveTexture1 = "map_emissive";
static const eastl::string EmissiveTexture2 = "map_Ke";
static const eastl::string BumpTexture1 = "map_bump";
static const eastl::string BumpTexture2 = "bump";
static const eastl::string NormalTextureV1 = "map_Kn";
static const eastl::string NormalTextureV2 = "norm";
static const eastl::string ReflectionTexture = "refl";
static const eastl::string DisplacementTexture1 = "map_disp";
static const eastl::string DisplacementTexture2 = "disp";
static const eastl::string SpecularityTexture = "map_ns";
static const eastl::string RoughnessTexture = "map_Pr";
static const eastl::string MetallicTexture = "map_Pm";
static const eastl::string SheenTexture = "map_Ps";
static const eastl::string RMATexture = "map_Ps";

// texture option specific token
static const eastl::string BlendUOption = "-blendu";
static const eastl::string BlendVOption = "-blendv";
static const eastl::string BoostOption = "-boost";
static const eastl::string ModifyMapOption = "-mm";
static const eastl::string OffsetOption = "-o";
static const eastl::string ScaleOption = "-s";
static const eastl::string TurbulenceOption = "-t";
static const eastl::string ResolutionOption = "-texres";
static const eastl::string ClampOption = "-clamp";
static const eastl::string BumpOption = "-bm";
static const eastl::string ChannelOption = "-imfchan";
static const eastl::string TypeOption = "-type";

// -------------------------------------------------------------------
//  Constructor
ObjFileMtlImporter::ObjFileMtlImporter(eastl::vector<char> &buffer,
        const eastl::string &,
        ObjFile::Model *pModel) :
        m_DataIt(buffer.begin()),
        m_DataItEnd(buffer.end()),
        m_pModel(pModel),
        m_uiLine(0),
        m_buffer() {
    ai_assert(nullptr != m_pModel);
    m_buffer.resize(BUFFERSIZE);
    eastl::fill(m_buffer.begin(), m_buffer.end(), '\0');
    if (nullptr == m_pModel->mDefaultMaterial) {
        m_pModel->mDefaultMaterial = new ObjFile::Material;
        m_pModel->mDefaultMaterial->MaterialName.Set("default");
    }
    load();
}

// -------------------------------------------------------------------
//  Destructor
ObjFileMtlImporter::~ObjFileMtlImporter() = default;

// -------------------------------------------------------------------
//  Loads the material description
void ObjFileMtlImporter::load() {
    if (m_DataIt == m_DataItEnd)
        return;

    while (m_DataIt != m_DataItEnd) {
        switch (*m_DataIt) {
            case 'k':
            case 'K': {
                ++m_DataIt;
                if (*m_DataIt == 'a') // Ambient color
                {
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getColorRGBA(&m_pModel->mCurrentMaterial->ambient);
                } else if (*m_DataIt == 'd') {
                    // Diffuse color
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getColorRGBA(&m_pModel->mCurrentMaterial->diffuse);
                } else if (*m_DataIt == 's') {
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getColorRGBA(&m_pModel->mCurrentMaterial->specular);
                } else if (*m_DataIt == 'e') {
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getColorRGBA(&m_pModel->mCurrentMaterial->emissive);
                }
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;
            case 'T': {
                ++m_DataIt;
                // Material transmission color
                if (*m_DataIt == 'f')  {
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getColorRGBA(&m_pModel->mCurrentMaterial->transparent);
                } else if (*m_DataIt == 'r')  {
                    // Material transmission alpha value
                    ++m_DataIt;
                    ai_real d;
                    getFloatValue(d);
                    if (m_pModel->mCurrentMaterial != nullptr)
                        m_pModel->mCurrentMaterial->alpha = static_cast<ai_real>(1.0) - d;
                }
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;
            case 'd': {
                if (*(m_DataIt + 1) == 'i' && *(m_DataIt + 2) == 's' && *(m_DataIt + 3) == 'p') {
                    // A displacement map
                    getTexture();
                } else {
                    // Alpha value
                    ++m_DataIt;
                    if (m_pModel->mCurrentMaterial != nullptr)
                        getFloatValue(m_pModel->mCurrentMaterial->alpha);
                    m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
                }
            } break;

            case 'N':
            case 'n': {
                ++m_DataIt;
                switch (*m_DataIt) {
                    case 's': // Specular exponent
                        ++m_DataIt;
                        if (m_pModel->mCurrentMaterial != nullptr)
                            getFloatValue(m_pModel->mCurrentMaterial->shineness);
                        break;
                    case 'i': // Index Of refraction
                        ++m_DataIt;
                        if (m_pModel->mCurrentMaterial != nullptr)
                            getFloatValue(m_pModel->mCurrentMaterial->ior);
                        break;
                    case 'e': // New material
                        createMaterial();
                        break;
                    case 'o': // Norm texture
                        --m_DataIt;
                        getTexture();
                        break;
                }
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;

            case 'P':
                {
                    ++m_DataIt;
                    switch(*m_DataIt)
                    {
                    case 'r':
                        ++m_DataIt;
                        if (m_pModel->mCurrentMaterial != nullptr)
                            getFloatValue(m_pModel->mCurrentMaterial->roughness);
                        break;
                    case 'm':
                        ++m_DataIt;
                        if (m_pModel->mCurrentMaterial != nullptr)
                            getFloatValue(m_pModel->mCurrentMaterial->metallic);
                        break;
                    case 's':
                        ++m_DataIt;
                        if (m_pModel->mCurrentMaterial != nullptr)
                            getColorRGBA(m_pModel->mCurrentMaterial->sheen);
                        break;
                    case 'c':
                        ++m_DataIt;
                        if (*m_DataIt == 'r') {
                            ++m_DataIt;
                            if (m_pModel->mCurrentMaterial != nullptr)
                                getFloatValue(m_pModel->mCurrentMaterial->clearcoat_roughness);
                        } else {
                            if (m_pModel->mCurrentMaterial != nullptr)
                                getFloatValue(m_pModel->mCurrentMaterial->clearcoat_thickness);
                        }
                        break;
                    }
                    m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
                }
                break;

            case 'm': // Texture
            case 'b': // quick'n'dirty - for 'bump' sections
            case 'r': // quick'n'dirty - for 'refl' sections
            {
                getTexture();
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;

            case 'i': // Illumination model
            {
                m_DataIt = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);
                if (m_pModel->mCurrentMaterial != nullptr)
                    getIlluminationModel(m_pModel->mCurrentMaterial->illumination_model);
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;

            case 'a': // Anisotropy
            {
                ++m_DataIt;
                getFloatValue(m_pModel->mCurrentMaterial->anisotropy);
                if (m_pModel->mCurrentMaterial != nullptr)
                    m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;

            default: {
                m_DataIt = skipLine<DataArrayIt>(m_DataIt, m_DataItEnd, m_uiLine);
            } break;
        }
    }
}

// -------------------------------------------------------------------
//  Loads a color definition
void ObjFileMtlImporter::getColorRGBA(aiColor3D *pColor) {
    ai_assert(nullptr != pColor);

    ai_real r(0.0), g(0.0), b(0.0);
    m_DataIt = getFloat<DataArrayIt>(m_DataIt, m_DataItEnd, r);
    pColor->r = r;

    // we have to check if color is default 0 with only one token
    if (!IsLineEnd(*m_DataIt)) {
        m_DataIt = getFloat<DataArrayIt>(m_DataIt, m_DataItEnd, g);
        m_DataIt = getFloat<DataArrayIt>(m_DataIt, m_DataItEnd, b);
    }
    pColor->g = g;
    pColor->b = b;
}

void ObjFileMtlImporter::getColorRGBA(Maybe<aiColor3D> &value) {
    aiColor3D v;
    getColorRGBA(&v);
    value = Maybe<aiColor3D>(v);
}

// -------------------------------------------------------------------
//  Loads the kind of illumination model.
void ObjFileMtlImporter::getIlluminationModel(int &illum_model) {
    m_DataIt = CopyNextWord<DataArrayIt>(m_DataIt, m_DataItEnd, &m_buffer[0], BUFFERSIZE);
    illum_model = atoi(&m_buffer[0]);
}


// -------------------------------------------------------------------
//  Loads a single float value.
void ObjFileMtlImporter::getFloatValue(ai_real &value) {
    m_DataIt = CopyNextWord<DataArrayIt>(m_DataIt, m_DataItEnd, &m_buffer[0], BUFFERSIZE);
    size_t len = strlen(&m_buffer[0]);
    if (0 == len) {
        value = 0.0f;
        return;
    }

    value = (ai_real)fast_atof(&m_buffer[0]);
}

void ObjFileMtlImporter::getFloatValue(Maybe<ai_real> &value) {
    m_DataIt = CopyNextWord<DataArrayIt>(m_DataIt, m_DataItEnd, &m_buffer[0], BUFFERSIZE);
    size_t len = strlen(&m_buffer[0]);
    if (len)
        value = Maybe<ai_real>(fast_atof(&m_buffer[0]));
    else
        value = Maybe<ai_real>();
}

// -------------------------------------------------------------------
//  Creates a material from loaded data.
void ObjFileMtlImporter::createMaterial() {
    eastl::string line;
    while (!IsLineEnd(*m_DataIt)) {
        line += *m_DataIt;
        ++m_DataIt;
    }

    eastl::vector<eastl::string> token;
    const unsigned int numToken = tokenize<eastl::string>(line, token, " \t");
    eastl::string name;
    if (numToken == 1) {
        name = AI_DEFAULT_MATERIAL_NAME;
    } else {
        // skip newmtl and all following white spaces
        size_t first_ws_pos = line.find_first_of(" \t");
        size_t first_non_ws_pos = line.find_first_not_of(" \t", first_ws_pos);
        if (first_non_ws_pos != eastl::string::npos) {
            name = line.substr(first_non_ws_pos);
        }
    }

    name = trim_whitespaces(name);

    eastl::map<eastl::string, ObjFile::Material *>::iterator it = m_pModel->mMaterialMap.find(name);
    if (m_pModel->mMaterialMap.end() == it) {
        // New Material created
        m_pModel->mCurrentMaterial = new ObjFile::Material();
        m_pModel->mCurrentMaterial->MaterialName.Set(name);
        m_pModel->mMaterialLib.push_back(name);
        m_pModel->mMaterialMap[name] = m_pModel->mCurrentMaterial;

        if (m_pModel->mCurrentMesh) {
            m_pModel->mCurrentMesh->m_uiMaterialIndex = static_cast<unsigned int>(m_pModel->mMaterialLib.size() - 1);
        }
    } else {
        // Use older material
        m_pModel->mCurrentMaterial = (*it).second;
    }
}

// -------------------------------------------------------------------
//  Gets a texture name from data.
void ObjFileMtlImporter::getTexture() {
    aiString *out(nullptr);
    int clampIndex = -1;

    const char *pPtr(&(*m_DataIt));
    if (!ASSIMP_strincmp(pPtr, DiffuseTexture.c_str(), static_cast<unsigned int>(DiffuseTexture.size()))) {
        // Diffuse texture
        out = &m_pModel->mCurrentMaterial->texture;
        clampIndex = ObjFile::Material::TextureDiffuseType;
    } else if (!ASSIMP_strincmp(pPtr, AmbientTexture.c_str(), static_cast<unsigned int>(AmbientTexture.size()))) {
        // Ambient texture
        out = &m_pModel->mCurrentMaterial->textureAmbient;
        clampIndex = ObjFile::Material::TextureAmbientType;
    } else if (!ASSIMP_strincmp(pPtr, SpecularTexture.c_str(), static_cast<unsigned int>(SpecularTexture.size()))) {
        // Specular texture
        out = &m_pModel->mCurrentMaterial->textureSpecular;
        clampIndex = ObjFile::Material::TextureSpecularType;
    } else if (!ASSIMP_strincmp(pPtr, DisplacementTexture1.c_str(), static_cast<unsigned int>(DisplacementTexture1.size())) ||
               !ASSIMP_strincmp(pPtr, DisplacementTexture2.c_str(), static_cast<unsigned int>(DisplacementTexture2.size()))) {
        // Displacement texture
        out = &m_pModel->mCurrentMaterial->textureDisp;
        clampIndex = ObjFile::Material::TextureDispType;
    } else if (!ASSIMP_strincmp(pPtr, OpacityTexture.c_str(), static_cast<unsigned int>(OpacityTexture.size()))) {
        // Opacity texture
        out = &m_pModel->mCurrentMaterial->textureOpacity;
        clampIndex = ObjFile::Material::TextureOpacityType;
    } else if (!ASSIMP_strincmp(pPtr, EmissiveTexture1.c_str(), static_cast<unsigned int>(EmissiveTexture1.size())) ||
               !ASSIMP_strincmp(pPtr, EmissiveTexture2.c_str(), static_cast<unsigned int>(EmissiveTexture2.size()))) {
        // Emissive texture
        out = &m_pModel->mCurrentMaterial->textureEmissive;
        clampIndex = ObjFile::Material::TextureEmissiveType;
    } else if (!ASSIMP_strincmp(pPtr, BumpTexture1.c_str(), static_cast<unsigned int>(BumpTexture1.size())) ||
               !ASSIMP_strincmp(pPtr, BumpTexture2.c_str(), static_cast<unsigned int>(BumpTexture2.size()))) {
        // Bump texture
        out = &m_pModel->mCurrentMaterial->textureBump;
        clampIndex = ObjFile::Material::TextureBumpType;
    } else if (!ASSIMP_strincmp(pPtr, NormalTextureV1.c_str(), static_cast<unsigned int>(NormalTextureV1.size())) || !ASSIMP_strincmp(pPtr, NormalTextureV2.c_str(), static_cast<unsigned int>(NormalTextureV2.size()))) {
        // Normal map
        out = &m_pModel->mCurrentMaterial->textureNormal;
        clampIndex = ObjFile::Material::TextureNormalType;
    } else if (!ASSIMP_strincmp(pPtr, ReflectionTexture.c_str(), static_cast<unsigned int>(ReflectionTexture.size()))) {
        // Reflection texture(s)
        //Do nothing here
        return;
    } else if (!ASSIMP_strincmp(pPtr, SpecularityTexture.c_str(), static_cast<unsigned int>(SpecularityTexture.size()))) {
        // Specularity scaling (glossiness)
        out = &m_pModel->mCurrentMaterial->textureSpecularity;
        clampIndex = ObjFile::Material::TextureSpecularityType;
    } else if ( !ASSIMP_strincmp( pPtr, RoughnessTexture.c_str(), static_cast<unsigned int>(RoughnessTexture.size()))) {
        // PBR Roughness texture
        out = & m_pModel->mCurrentMaterial->textureRoughness;
        clampIndex = ObjFile::Material::TextureRoughnessType;
    } else if ( !ASSIMP_strincmp( pPtr, MetallicTexture.c_str(), static_cast<unsigned int>(MetallicTexture.size()))) {
        // PBR Metallic texture
        out = & m_pModel->mCurrentMaterial->textureMetallic;
        clampIndex = ObjFile::Material::TextureMetallicType;
    } else if (!ASSIMP_strincmp( pPtr, SheenTexture.c_str(), static_cast<unsigned int>(SheenTexture.size()))) {
        // PBR Sheen (reflectance) texture
        out = & m_pModel->mCurrentMaterial->textureSheen;
        clampIndex = ObjFile::Material::TextureSheenType;
    } else if (!ASSIMP_strincmp( pPtr, RMATexture.c_str(), static_cast<unsigned int>(RMATexture.size()))) {
        // PBR Rough/Metal/AO texture
        out = & m_pModel->mCurrentMaterial->textureRMA;
        clampIndex = ObjFile::Material::TextureRMAType;
    } else {
        ASSIMP_LOG_ERROR("OBJ/MTL: Encountered unknown texture type");
        return;
    }

    bool clamp = false;
    getTextureOption(clamp, clampIndex, out);
    m_pModel->mCurrentMaterial->clamp[clampIndex] = clamp;

    eastl::string texture;
    m_DataIt = getName<DataArrayIt>(m_DataIt, m_DataItEnd, texture);
    if (nullptr != out) {
        out->Set(texture);
    }
}

/* /////////////////////////////////////////////////////////////////////////////
 * Texture Option
 * /////////////////////////////////////////////////////////////////////////////
 * According to http://en.wikipedia.org/wiki/Wavefront_.obj_file#Texture_options
 * Texture map statement can contains various texture option, for example:
 *
 *  map_Ka -o 1 1 1 some.png
 *  map_Kd -clamp on some.png
 *
 * So we need to parse and skip these options, and leave the last part which is
 * the url of image, otherwise we will get a wrong url like "-clamp on some.png".
 *
 * Because aiMaterial supports clamp option, so we also want to return it
 * /////////////////////////////////////////////////////////////////////////////
 */
void ObjFileMtlImporter::getTextureOption(bool &clamp, int &clampIndex, aiString *&out) {
    m_DataIt = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);

    // If there is any more texture option
    while (!isEndOfBuffer(m_DataIt, m_DataItEnd) && *m_DataIt == '-') {
        const char *pPtr(&(*m_DataIt));
        //skip option key and value
        int skipToken = 1;

        if (!ASSIMP_strincmp(pPtr, ClampOption.c_str(), static_cast<unsigned int>(ClampOption.size()))) {
            DataArrayIt it = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);
            char value[3];
            CopyNextWord(it, m_DataItEnd, value, sizeof(value) / sizeof(*value));
            if (!ASSIMP_strincmp(value, "on", 2)) {
                clamp = true;
            }

            skipToken = 2;
        } else if (!ASSIMP_strincmp(pPtr, TypeOption.c_str(), static_cast<unsigned int>(TypeOption.size()))) {
            DataArrayIt it = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);
            char value[12];
            CopyNextWord(it, m_DataItEnd, value, sizeof(value) / sizeof(*value));
            if (!ASSIMP_strincmp(value, "cube_top", 8)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeTopType;
                out = &m_pModel->mCurrentMaterial->textureReflection[0];
            } else if (!ASSIMP_strincmp(value, "cube_bottom", 11)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeBottomType;
                out = &m_pModel->mCurrentMaterial->textureReflection[1];
            } else if (!ASSIMP_strincmp(value, "cube_front", 10)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeFrontType;
                out = &m_pModel->mCurrentMaterial->textureReflection[2];
            } else if (!ASSIMP_strincmp(value, "cube_back", 9)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeBackType;
                out = &m_pModel->mCurrentMaterial->textureReflection[3];
            } else if (!ASSIMP_strincmp(value, "cube_left", 9)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeLeftType;
                out = &m_pModel->mCurrentMaterial->textureReflection[4];
            } else if (!ASSIMP_strincmp(value, "cube_right", 10)) {
                clampIndex = ObjFile::Material::TextureReflectionCubeRightType;
                out = &m_pModel->mCurrentMaterial->textureReflection[5];
            } else if (!ASSIMP_strincmp(value, "sphere", 6)) {
                clampIndex = ObjFile::Material::TextureReflectionSphereType;
                out = &m_pModel->mCurrentMaterial->textureReflection[0];
            }

            skipToken = 2;
        } else if (!ASSIMP_strincmp(pPtr, BumpOption.c_str(), static_cast<unsigned int>(BumpOption.size()))) {
            DataArrayIt it = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);
            getFloat(it, m_DataItEnd, m_pModel->mCurrentMaterial->bump_multiplier);
            skipToken = 2;
        } else if (!ASSIMP_strincmp(pPtr, BlendUOption.c_str(), static_cast<unsigned int>(BlendUOption.size())) || !ASSIMP_strincmp(pPtr, BlendVOption.c_str(), static_cast<unsigned int>(BlendVOption.size())) || !ASSIMP_strincmp(pPtr, BoostOption.c_str(), static_cast<unsigned int>(BoostOption.size())) || !ASSIMP_strincmp(pPtr, ResolutionOption.c_str(), static_cast<unsigned int>(ResolutionOption.size())) || !ASSIMP_strincmp(pPtr, ChannelOption.c_str(), static_cast<unsigned int>(ChannelOption.size()))) {
            skipToken = 2;
        } else if (!ASSIMP_strincmp(pPtr, ModifyMapOption.c_str(), static_cast<unsigned int>(ModifyMapOption.size()))) {
            skipToken = 3;
        } else if (!ASSIMP_strincmp(pPtr, OffsetOption.c_str(), static_cast<unsigned int>(OffsetOption.size())) || !ASSIMP_strincmp(pPtr, ScaleOption.c_str(), static_cast<unsigned int>(ScaleOption.size())) || !ASSIMP_strincmp(pPtr, TurbulenceOption.c_str(), static_cast<unsigned int>(TurbulenceOption.size()))) {
            skipToken = 4;
        }

        for (int i = 0; i < skipToken; ++i) {
            m_DataIt = getNextToken<DataArrayIt>(m_DataIt, m_DataItEnd);
        }
    }
}

// -------------------------------------------------------------------

} // Namespace Assimp

#endif // !! ASSIMP_BUILD_NO_OBJ_IMPORTER
