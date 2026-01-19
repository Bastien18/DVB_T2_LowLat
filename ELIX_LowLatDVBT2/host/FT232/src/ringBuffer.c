/**
 * File: ringBuffer.c
 * Author: Bastien Pillonel
 * Email: bastien.pillonel@heig-vd.ch
 * 
 * Description: This file implement functions needed to handle simple
 *              ring buffer data structure
 * 
 */

#include "ringBuffer.h"
#include <stdlib.h>

int rbInit(ringBuffer_t *rb, size_t capacity, size_t blockSize){
    rb->buffer = calloc(rb->capacity, sizeof(block_t));
    if(!rb->buffer){
        return -1;
    }
    rb->bufferEnd = rb->buffer + (capacity * sizeof(block_t));
    rb->capacity = capacity;
    rb->count = 0;
    rb->head = rb->buffer;
    rb->tail = rb->buffer;

    for(size_t i = 0; i < capacity; ++i){
        rb->buffer[i].data = (uint8_t *)malloc(blockSize);
        rb->buffer[i].len = 0;
        rb->buffer[i].eof = 0;
    }

    pthread_mutex_init(&rb->mutex, NULL);
    pthread_cond_init(&rb->cvNotEmpty, NULL);
    pthread_cond_init(&rb->cvNotFull, NULL);

    return 0;
}

void rbFree(ringBuffer_t *rb){
    for(size_t i = 0; i < rb->capacity; ++i){
        free(rb->buffer[i].data);
    }
    free(rb->buffer);
    pthread_mutex_destroy(&rb->mutex);
    pthread_cond_destroy(&rb->cvNotEmpty);
    pthread_cond_destroy(&rb->cvNotFull);
}

block_t* rbAcquireWriteSlot(ringBuffer_t *rb){
    pthread_mutex_lock(&rb->mutex);
    // While buffer full, wait for consumer to free some space 
    while(rb->count == rb->capacity){
        pthread_cond_wait(&rb->cvNotFull, &rb->mutex);
    }
    block_t *b = rb->tail;
    pthread_mutex_unlock(&rb->mutex);
    return b;
}

void *rbCommitWriteSlot(ringBuffer_t *rb, int eof){
    pthread_mutex_lock(&rb->mutex);
    // If we've reached end of file for this last block 
    rb->tail->eof = eof;
    rb->tail = rb->tail + sizeof(block_t);
    if(rb->tail == rb->bufferEnd){
        rb->tail = rb->buffer;
    }
    rb->count++;
    pthread_cond_signal(&rb->cvNotEmpty);
    pthread_mutex_unlock(&rb->mutex);
}

block_t rbPop(ringBuffer_t *rb){
    block_t b = {0};
    pthread_mutex_lock(&rb->mutex);
    while(rb->count == 0){
        pthread_cond_wait(&rb->cvNotEmpty, &rb->mutex);
    }
    b = *rb->head;
    rb->head = rb->head +sizeof(block_t);
    if (rb->head == rb->bufferEnd){
        rb->head = rb->buffer;
    }
    rb->count--;
    pthread_cond_signal(&rb->cvNotFull);
    pthread_mutex_unlock(&rb->mutex);
    return b;
}