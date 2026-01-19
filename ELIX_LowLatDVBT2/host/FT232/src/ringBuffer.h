#ifndef RINGBUFFER_H
#define RINGBUFFER_H

#include <stdint.h>
#include <pthread.h>

typedef struct {
    uint8_t* data;              // Ptr on the first byte of the block
    size_t len;                 // Size of the block
    int eof;                    // Flag telling if it's the last block of data from the file
} block_t;

typedef struct {
    block_t *buffer;            // Data buffer
    block_t *bufferEnd;         // End of block buffer
    size_t capacity;            // Max number of items in the buffer
    size_t count;               // Number of items int the buffer
    block_t *head;              // Ptr to head
    block_t *tail;              // Ptr to tail
    pthread_mutex_t mutex;      // Mutex preventing access by multiple thread
    pthread_cond_t cvNotEmpty;  // Make consumer thread wait when buffer is empty
    pthread_cond_t cvNotFull;   // Make producer thread wait when buffer is full
} ringBuffer_t;

/**
 * @brief Initialize ring buffer with specified capacity and item size
 * @param rb        Pointer to ring buffer to initialize
 * @param capacity  Number of item max allowed in the buffer
 * @param blockSize Size of a single block stored in the buffer
 * @return -1 if malloc of buffer failed, 0 instead
 */
int rbInit(ringBuffer_t *rb, size_t capacity, size_t blockSize);

/**
 * @brief           Free up memory allocated for the ring buffer
 * @param rb        Ptr to ring buffer 
 */
void rbFree(ringBuffer_t *rb);

/**
 * @brief           Wait until a free block space comes up inside the ring buffer
 *                  and return a ptr to first free block
 * @param rb        Ptr to ring buffer
 * @return          Ptr to first free block
 */
block_t *rbAcquireWriteSlot(ringBuffer_t *rb);

/**
 * @brief           Advance
 * @param           
 * @param           
 * @return          
 */
void *rbCommitWriteSlot(ringBuffer_t *rb, int eof);

/**
 * @brief           Wait for buffer to have blocks inside it and pops first block
 *                  that arrived in the buffer (head)
 * @param rb        Ptr to ring buffer
 * @return          Ptr to the block popped
 */
block_t rbPop(ringBuffer_t *rb);


#endif

