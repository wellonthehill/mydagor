//
// Dagor Engine 6.5
// Copyright (C) 2023  Gaijin Games KFT.  All rights reserved
// (for conditions of use see prog/license.txt)
//
#pragma once

// this is very simple and totally not thread-safe allocator which allocates memory in blocks of fixed size
// it uses buddy-allocator (i.e. allocating memory in chunks growing in power-of-2)
// maximum chunk size is limited to 32768 (can be made bigger, but in case of regular allocator 32768 blocks are 512kb!)
// if allocating (and de-allocating) in order, performance will be 10X times faster than dlmalloc (for blocks of 16 bytes)
// if de-allocating out of order, performance will be 2X times faster than dlmalloc (for blocks of 16 bytes)
// the best property of it, is that it is allocating memory tight (no service information or padding)
// minimum block size is 4 bytes (i.e. if you will use it for smaller blocks, it will waste space)
// NOTE! it doesn't keep alignment of 16 if block size is not 16 bytes aligned!
// if you want to align to 16 block of different size, you can use align_to_if_bigger
// if you want to have such alignment (probably for bigger chunks, use aligned block size)

// intentionally made with minimum dependencies (we actually need base types and G_ASSERT only, besides memcpy/memset)


#include <memory.h>
#include <string.h>
#include <memory/dag_memBase.h>
#include <util/dag_globDef.h>
#include <util/dag_stdint.h>

#define FBA_MIN_BLOCKS 4u // minimum block size should allow storing free block index

#if !defined(DAGOR_PREFER_HEAP_ALLOCATION) || DAGOR_PREFER_HEAP_ALLOCATION == 0

#if DAGOR_DBGLEVEL > 0 && _DEBUG_TAB_
#if defined(_M_IX86_FP) && _M_IX86_FP == 0
#define FBA_MIN4K(x) x
#else
#define FBA_MIN4K(x) min<unsigned>(x, 4096u)
#endif
#define FBA_DEBUG_FILL_MEM(p, sz, ptrn)                                   \
  for (int *i = (int *)(p), *e = i + FBA_MIN4K(sz / sizeof(int)); i < e;) \
  *i++ = ptrn
#else
#define FBA_DEBUG_FILL_MEM(p, sz, ptrn)
#endif

struct FixedBlockAllocator
{
protected:
  struct Chunk;

public:
  void *allocateOneBlock();   // of block size
  bool freeOneBlock(void *b); // return false, if block doesn't belong to allocator. Warning, double delete isn't checked in dev build
                              // (would require iteration)
  void *allocateContiguousBlocks(unsigned block_cnt);     // of block size * block_cnt total
  bool freeContiguousBlocks(void *b, unsigned block_cnt); // return false, if block doesn't belong to allocator. Warning, double delete
                                                          // isn't checked in dev build (would require iteration)

  Chunk *isValidPtr(void *b) const; // return not nullptr if pointer resides in ranges controlled by this allocator

  int clear();                   // return number of blocks that was freed
  uint32_t getBlockSize() const; // return block size
  void getMemoryStats(uint32_t &chunks_count, uint32_t &allocated_mem, uint32_t &used_mem);

  // memory is 16 byte only if block_size is 16 bytes aligned. If you need bigger than alignment blocks to be aligned - align memory by
  // this function
  static constexpr uint32_t align_to_if_bigger(uint32_t block, uint32_t alignment);

  FixedBlockAllocator() = default; // If this ctor is used then init() has to be called before first allocation
  FixedBlockAllocator(uint32_t block_size, uint16_t min_chunk_size_in_blocks);
  FixedBlockAllocator(FixedBlockAllocator &&);
  FixedBlockAllocator &operator=(FixedBlockAllocator &&);
  FixedBlockAllocator(const FixedBlockAllocator &) = delete;
  FixedBlockAllocator &operator=(const FixedBlockAllocator &) = delete;
  ~FixedBlockAllocator();

  void init(uint32_t block_size, uint16_t min_chunk_size_in_blocks); // Need to be called if default ctor is used. Warn: can be called
                                                                     // only before first allocation
  bool isInited() const;                                             // return false if init or non default ctor wasn't called

protected:
  struct Chunk
  {
    static constexpr int MAX_CHUNK_SIZE = 32768; // there is enough bits to allocate as 17 bit used, 17 bit freeBlock, 17(or 4 for
                                                 // pow-of-2) bit chunkSize
    char *blocks = nullptr;
    uint16_t used = 0;
    uint16_t chunkSize = 0; // can be 17 : 5 for 65536 blocks
    uint32_t freeBlock = 0;

    uint32_t getChunkSize() const { return chunkSize; } // at least of size one. could be used with shifts if pow-of-2
    uint32_t getUsedSize() const { return used; }       // at least one block should be always allocated (for 64k blocks)
    uint32_t getFreeHead() const { return freeBlock; }
    int spaceLeft() const { return getChunkSize() - getUsedSize(); }
    // uint32_t getInitialEnd() const { return initialEnd; }
    uint32_t allocateOne(uint32_t block_size) // we need to pass blocks and block_size, so we can use freelist within blocks
    {
      G_ASSERTF(spaceLeft() > 0, "FixedAllocator %p: chunk is full!", this);
      used++;
      const uint32_t chunkSz = getChunkSize();
      // if (getInitialEnd() != getChunkSize())
      //   return initialEnd++;
      const uint32_t freeHead = getFreeHead();
      G_ASSERTF(freeHead < chunkSz, "FixedAllocator %p:free linked list block in chunk is invalid (%d>=%d)", this, freeBlock, chunkSz);
      G_ASSERTF_RETURN(freeHead != chunkSz, -1, "FixedAllocator %p:no free blocks in chunk, while chunk is not full", this);
      freeBlock = *(uint32_t *)(blocks + block_size * freeHead);
      G_ASSERTF(freeBlock < chunkSz || getUsedSize() == chunkSz,
        "FixedAllocator %p:free linked list block in chunk is invalid (%d>=%d)", this, freeBlock, chunkSz);

      return freeHead;
    }
    uint32_t allocateBlocks(uint32_t block_size, uint32_t block_cnt) // we need to pass blocks and block_size, so we can use freelist
                                                                     // within blocks
    {
      G_ASSERTF(spaceLeft() >= block_cnt, "FixedAllocator %p: chunk is full!", this);
      const uint32_t chunkSz = getChunkSize();
      uint32_t preFirstFree = chunkSz, firstFree = getFreeHead(), lastFree = firstFree;
      G_ASSERTF(firstFree < chunkSz, "FixedAllocator %p:free linked list block in chunk is invalid (%d>=%d)", this, freeBlock,
        chunkSz);
      while (lastFree - firstFree + 1 < block_cnt)
      {
        uint32_t next_b = *(uint32_t *)(blocks + block_size * lastFree);
        if (next_b >= chunkSz)
          return chunkSz;
        else if (next_b == lastFree + 1)
          lastFree++;
        else
        {
          preFirstFree = lastFree;
          firstFree = lastFree = next_b;
        }
      }

      if (preFirstFree == chunkSz)
        freeBlock = *(uint32_t *)(blocks + block_size * lastFree);
      else
        *(uint32_t *)(blocks + block_size * preFirstFree) = *(uint32_t *)(blocks + block_size * lastFree);
      used += block_cnt;
      return firstFree;
    }
    bool freeBlocks(uint32_t block, uint32_t block_size, uint32_t block_cnt) // we need to pass blocks and block_size, so we can use
                                                                             // freelist within blocks
    {
      G_ASSERTF_RETURN(block < getChunkSize(), false, "FixedAllocator %p: block is out of range", this);
#if FA_65536_BLOCK_ALLOWED
      if (getUsedSize() == block_cnt) // chunks should be killed
      {
        used -= block_cnt; // only if below 32768
        return true;
      }
#endif
      G_ASSERTF_RETURN(getUsedSize(), false, "FixedAllocator %p: block is out of range", this);
#if !FA_65536_BLOCK_ALLOWED && DAGOR_DBGLEVEL > 1
      for (uint32_t check = freeBlock, chunkSz = getChunkSize(); check < chunkSz; check = *(uint32_t *)(blocks + block_size * check))
        if (check >= block && check < block + block_cnt)
          G_ASSERTF_RETURN(0, false, "FixedAllocator %p(blockSize=%d): block (%d;%d) is already deleted!", this, block_size, block,
            block_cnt);
#endif
      // const uint32_t chunkSize = getChunkSize();
      // const uint32_t currentInitialEnd = getInitialEnd();
      // if (currentInitialEnd == getUsedSize() && currentInitialEnd != chunkSize)//we hadn't finished allocating, and can just pop
      // from end
      //{
      //   G_ASSERT(initialEnd > 0);
      //   initialEnd--;
      // } else
      used -= block_cnt;
      block += block_cnt - 1;
      do
      {
        *(uint32_t *__restrict)(blocks + block_size * block) = freeBlock; // old head of linked goes to freed block
        freeBlock = block;                                                // change head of linked list
        --block;
      } while (--block_cnt);
      return used == 0;
    }

    ~Chunk() = delete;
    Chunk() = default;
    Chunk(Chunk &&a)
    {
      memcpy(this, &a, sizeof(Chunk));
      a.blocks = nullptr;
    }
    // Chunk &operator =(Chunk &&a){swap(*this, a);}
    Chunk &operator=(const Chunk &) = delete;
    Chunk(const Chunk &) = delete;
    void create(char *b, uint32_t block_size, uint32_t chunk_size)
    {
      G_ASSERT(chunk_size <= 32768);
      G_ASSERT(block_size >= 4);
      blocks = b;
      chunkSize = chunk_size;
      for (uint32_t i = 0; i < chunk_size; ++i, b += block_size)
        *((uint32_t *)b) = i + 1;
    }
  };
  Chunk *chunks = nullptr;
  uint32_t blockSize = 0;
  uint16_t chunksAllocated = 0;
  uint16_t minChunkSize = 0;

  void removeChunk(Chunk *chunk)
  {
    G_ASSERT(chunk >= chunks && chunk < chunks + chunksAllocated);
    G_ASSERT(chunk->blocks);
    delete[] chunk->blocks; // free memory
    Chunk *c = chunk + 1;
    for (Chunk *e = chunks + chunksAllocated; c != e && c->blocks; ++c)
      ;
    c--;
    if (c != chunk)
      memcpy(chunk, c, sizeof(Chunk));
    memset(c, 0, sizeof(Chunk)); // reset to zero
  }
  bool allocateChunkMemory(Chunk &c, uint32_t chunk_size) const
  {
    G_ASSERT(chunk_size > 0 && chunk_size <= Chunk::MAX_CHUNK_SIZE);
    char *memory = new char[chunk_size * blockSize];
    if (!memory)
      return false;
    c.create(memory, blockSize, chunk_size);
    return true;
  }
  int allocateChunk(uint32_t chunk_size)
  {
    if (chunk_size > Chunk::MAX_CHUNK_SIZE)
      chunk_size = Chunk::MAX_CHUNK_SIZE;
    // debug("new chunk of %d", chunk_size);
    uint32_t ret = 0;
    for (; ret != chunksAllocated; ++ret)
      if (!chunks[ret].blocks)
        break;
    if (ret == chunksAllocated)
    {
      static const uint32_t minChunksCount = 4; // we allocate at least 4 chunks.
      const uint32_t newChunksAllocated = chunksAllocated == 0 ? minChunksCount : chunksAllocated * 2;
      Chunk *newChunks = (Chunk *)new char[sizeof(Chunk) * newChunksAllocated];
      if (!newChunks)
        return -1;
      memcpy(newChunks, chunks, sizeof(Chunk) * chunksAllocated);
      memset(newChunks + chunksAllocated, 0, sizeof(Chunk) * (newChunksAllocated - chunksAllocated));
      if (chunks)
        delete[] ((char *)chunks);
      chunks = newChunks;
      chunksAllocated = newChunksAllocated;
      // debug("new chunks %d", newChunksAllocated);
    }
    swap_chunks(chunks, chunks + ret);
    return allocateChunkMemory(chunks[0], chunk_size) ? 0 : -1;
  }
  uint32_t getNextSize() const
  {
    uint32_t size = 0;
    for (Chunk *c = chunks, *e = chunks + chunksAllocated; c != e && c->blocks; ++c)
      size = max(size, c->getChunkSize());

    return size ? size * 2 : minChunkSize;
  }
  static void swap_chunks(Chunk *a, Chunk *b)
  {
    if (a == b)
      return;
    char temp[sizeof(Chunk)];
    memcpy(temp, a, sizeof(Chunk));
    memcpy(a, b, sizeof(Chunk));
    memcpy(b, temp, sizeof(Chunk));
  }
  bool validateAllocatingHead(int block_cnt = 1)
  {
    if (!chunks)
      return false;
    if (chunks->spaceLeft() >= block_cnt)
      return true;
    for (Chunk *c = chunks, *e = chunks + chunksAllocated; c != e && c->blocks; ++c)
      if (c->spaceLeft() >= block_cnt)
      {
        // swap
        swap_chunks(c, chunks);
        return true; // now head has space left
      }
    return false;
  }
};

inline FixedBlockAllocator::~FixedBlockAllocator()
{
  int nb = clear();
  G_UNUSED(nb);
  G_ASSERTF(nb == 0, "Memory leak in fixed block size allocator of block %d (leaked %d blocks)", blockSize, nb);
}

inline int FixedBlockAllocator::clear()
{
  int nblocks = 0;
  for (Chunk *c = chunks, *e = chunks + chunksAllocated; c != e; ++c)
    if (c->blocks)
    {
      nblocks += c->getUsedSize();
      delete[] c->blocks; // free memory
    }
  if (chunks)
    delete[] ((char *)chunks);
  chunks = nullptr;
  chunksAllocated = 0;
  return nblocks;
}

inline void *FixedBlockAllocator::allocateOneBlock() // of block size
{
  G_FAST_ASSERT(isInited());
  if (!validateAllocatingHead())
    allocateChunk(getNextSize());
  G_ASSERT(chunks);
  uint32_t block = chunks->allocateOne(blockSize);
  void *mem = chunks->blocks + block * blockSize;
  FBA_DEBUG_FILL_MEM(mem, blockSize, 0x7ffdcdcd);
  return mem;
}
inline void *FixedBlockAllocator::allocateContiguousBlocks(unsigned block_cnt) // of block size * block_cnt total
{
  G_FAST_ASSERT(isInited());
  if (!validateAllocatingHead(block_cnt))
    allocateChunk(getNextSize());
  G_ASSERT(chunks);
  uint32_t block = chunks->allocateBlocks(blockSize, block_cnt);
  if (block == chunks->getChunkSize())
  {
    allocateChunk(getNextSize());
    block = chunks->allocateBlocks(blockSize, block_cnt);
    G_ASSERTF_RETURN(block < chunks->getChunkSize(), nullptr, "block_cnt=%d chunkSize=%d spaceleft=%d", block_cnt,
      chunks->getChunkSize(), chunks->spaceLeft());
  }
  void *mem = chunks->blocks + block * blockSize;
  FBA_DEBUG_FILL_MEM(mem, blockSize * block_cnt, 0x7ffdcdcd);
  return mem;
}

inline uint32_t FixedBlockAllocator::getBlockSize() const { return blockSize; }
inline bool FixedBlockAllocator::isInited() const { return getBlockSize() != 0u; }

inline void FixedBlockAllocator::getMemoryStats(uint32_t &chunks_count, uint32_t &allocated_mem, uint32_t &used_mem)
{
  chunks_count = chunksAllocated;
  used_mem = allocated_mem = 0;
  for (Chunk *c = chunks, *e = chunks + chunksAllocated; c != e && c->blocks; ++c)
  {
    allocated_mem += c->getChunkSize();
    used_mem += c->getUsedSize();
  }
  allocated_mem *= blockSize;
  used_mem *= blockSize;
}

inline FixedBlockAllocator::Chunk *FixedBlockAllocator::isValidPtr(void *b) const
{
  G_FAST_ASSERT(isInited());
  for (Chunk *c = chunks, *e = chunks + chunksAllocated; c != e && c->blocks; ++c)
    if (c->blocks <= b && b < c->blocks + c->getChunkSize() * blockSize)
      return c;
  return nullptr;
}

inline bool FixedBlockAllocator::freeContiguousBlocks(void *b, unsigned block_cnt)
{
  G_FAST_ASSERT(isInited());
  if (!block_cnt)
    return false;
  if (Chunk *c = isValidPtr(b))
  {
    const uintptr_t blockPtr = ((char *)b - c->blocks);
    G_ASSERT(blockPtr % blockSize == 0); // deallocating pointer to middle of some block;
    G_ASSERT(blockPtr + blockSize * block_cnt <= c->getChunkSize() * blockSize);
    FBA_DEBUG_FILL_MEM(b, blockSize * block_cnt, 0x7ffddddd);
    if (c->freeBlocks(blockPtr / blockSize, blockSize, block_cnt)) // chunk is empty removed.
      removeChunk(c);
    return true;
  }
  return false;
}
inline bool FixedBlockAllocator::freeOneBlock(void *b) { return freeContiguousBlocks(b, 1); }

// memory is 16 byte only if block_size is 16 bytes aligned. If you need always aligned - align memory by it
inline FixedBlockAllocator::FixedBlockAllocator(uint32_t block_size, uint16_t min_chunk_size) :
  blockSize(max(block_size, FBA_MIN_BLOCKS)), minChunkSize(max(min_chunk_size, decltype(minChunkSize)(1)))
{}

inline void FixedBlockAllocator::init(uint32_t block_size, uint16_t min_chunk_size)
{
  G_ASSERTF(!chunks, "%s should be called before first allocation", __FUNCTION__);
  blockSize = max(block_size, FBA_MIN_BLOCKS);
  minChunkSize = max(min_chunk_size, decltype(minChunkSize)(1));
}

inline FixedBlockAllocator::FixedBlockAllocator(FixedBlockAllocator &&a) :
  chunks(a.chunks), chunksAllocated(a.chunksAllocated), blockSize(a.blockSize), minChunkSize(a.minChunkSize)
{
  a.chunks = nullptr;
  a.chunksAllocated = 0;
}

inline FixedBlockAllocator &FixedBlockAllocator::operator=(FixedBlockAllocator &&a)
{
  chunks = a.chunks;
  chunksAllocated = a.chunksAllocated;
  blockSize = a.blockSize;
  minChunkSize = a.minChunkSize;
  a.chunks = nullptr;
  a.chunksAllocated = 0;
  return *this;
}

inline constexpr uint32_t FixedBlockAllocator::align_to_if_bigger(uint32_t block, uint32_t alignment)
{
  return block <= alignment ? block : alignment * ((block + alignment - 1) / alignment);
}
#undef FBA_DEBUG_FILL_MEM
#undef FBA_MIN4K

#else // DAGOR_PREFER_HEAP_ALLOCATION

struct FixedBlockAllocator
{
  FixedBlockAllocator() = default;
  FixedBlockAllocator(uint32_t block_size, uint16_t) : blockSize(max(block_size, FBA_MIN_BLOCKS)) {}
  void init(uint32_t block_size, uint16_t) { blockSize = max(block_size, FBA_MIN_BLOCKS); }
  bool isInited() const { return getBlockSize() != 0u; }
  void *allocateOneBlock()
  {
    G_FAST_ASSERT(isInited());
    return memalloc(blockSize);
  }
  bool freeOneBlock(void *b)
  {
    G_FAST_ASSERT(isInited());
    memfree_anywhere(b);
    return true;
  }
  void *allocateContiguousBlocks(unsigned block_cnt)
  {
    G_FAST_ASSERT(isInited());
    return memalloc(block_cnt * blockSize);
  }
  bool freeContiguousBlocks(void *b, unsigned)
  {
    G_FAST_ASSERT(isInited());
    memfree_anywhere(b);
    return true;
  }
  void *isValidPtr(void *) const { return (void *)this; }
  int clear() { return 0; }
  uint32_t getBlockSize() const { return blockSize; }
  void getMemoryStats(uint32_t &a, uint32_t &b, uint32_t &c) { a = b = c = 0; }

private:
  uint32_t blockSize = 0;
};

#endif // DAGOR_PREFER_HEAP_ALLOCATION
