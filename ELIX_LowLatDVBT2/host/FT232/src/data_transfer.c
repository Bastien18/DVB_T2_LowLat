/**
 * File: data_transfer.c
 * Author: Bastien Pillonel
 * Email: bastien.pillonel@heig-vd.ch
 * 
 * Description: This file implement function related to the transfer of TS data from host computer
 *              to the FTDI device.
 * 
 */

#include "data_transfer.h"
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

int initFt(FT_HANDLE *ftHandle, ULONG ftPurge, ULONG uInTransferSize, ULONG uOutTransferSize, ULONG uLatency, ULONG uReadTimeout, ULONG uWriteTimeout, ULONG uEnable){
    FT_STATUS ftStatus = FT_Open(0, ftHandle);

    if(ftStatus != FT_OK){
        dieFt("FT_Open failed", ftStatus);
    }

    // Clean init with reset and purge (is optional)
    ftStatus = FT_ResetDevice(*ftHandle);
    if(ftStatus != FT_OK){
        dieFt("FT_ResetDevice failed", ftStatus);
    }

    ftStatus = FT_Purge(*ftHandle, ftPurge);
    if(ftStatus != FT_OK){
        dieFt("FT_Purge failed", ftStatus);
    }

    // Throughput related tunning
    ftStatus = FT_SetUSBParameters(*ftHandle, uInTransferSize, uOutTransferSize);
    if(ftStatus != FT_OK){
        dieFt("FT_SetUSBParameters failed", ftStatus);
    }

    ftStatus = FT_SetLatencyTimer(*ftHandle, uLatency);
    if(ftStatus != FT_OK){
        dieFt("FT_SetLatencyTimer failed", ftStatus);
    }

    ftStatus = FT_SetTimeouts(*ftHandle, uReadTimeout, uWriteTimeout);
    if(ftStatus != FT_OK){
        dieFt("FT_SetTimeouts failed", ftStatus);
    }

    // Set bitmode 0x40 for Sync FIFO application 
    ftStatus = FT_SetBitMode(*ftHandle, 0xff, uEnable);
    if(ftStatus != FT_OK){
        dieFt("FT_SetBitMode failed", ftStatus);
    }

    return 0;
}

void dieFt(const char* msg, FT_STATUS ftStatus){
    LOG_ERROR("%s (FT_Status=%d)\n", msg, (int)ftStatus);
    exit(1);
}

int startTransferFt(FT_HANDLE ftHandle, const char *filename){

    // Initialize ring buffer for TS data
    ringBuffer_t rBuffer;
    if(rbInit(&rBuffer, RING_BUFFER_CAPACITY, RING_BUFFER_BLOCK_SIZE)){
        LOG_ERROR("Error during ring buffer init");
        return 1;
    }

    // Initialize consumer and producer thread
    pthread_t consumerThread;
    pthread_t producerThread;

    consArgs_t consArgs = {.ftHandle = ftHandle, .ring = &rBuffer};
    prodArgs_t prodArgs = {.blockSize = RING_BUFFER_BLOCK_SIZE, .filename = filename, .ring = &rBuffer};

    pthread_create(&consumerThread, NULL, consumerCall, (void *)&consArgs);
    pthread_create(&producerThread, NULL, producerCall, (void *)&prodArgs);

    // Waiting for both threads to end
    pthread_join(consumerThread, NULL);
    pthread_join(producerThread, NULL);

    // Clean up resources
    rbFree(&rBuffer);

    return 0;
}

int writeAllFt(consArgs_t *consArgs, uint8_t* buf, DWORD len){
    DWORD offset = 0;
    while(offset < len){
        DWORD written = 0;
        FT_STATUS ftStatus = FT_Write(consArgs->ftHandle, buf + offset, len - offset, &written);

        if(ftStatus != FT_OK){
            LOG_ERROR("FT_Write failed: %d", ftStatus);
            return 0;
        }

        if(!written){
            // Check for a stall from FTDI device. Add a sleep call to avoid tight infinite loop
            printf("[WARNING]FT_Write() operation wrote 0byte. Check for anormal stall from FTDI\n");
            usleep(1000);
            continue;
        }
        offset += written;
    }
    return 1;
}

void *producerCall(void *args){
    prodArgs_t *prodArgs = (prodArgs_t *)args;
    // Handling file opening
    FILE *f = fopen(prodArgs->filename, "rb");
    if(!f){
        LOG_ERROR("Something went wrong opening file %s", prodArgs->filename);
        rbAbort(prodArgs->ring);
        return NULL;
    }

    while(1){
        block_t *block = rbAcquireWriteSlot(prodArgs->ring);
        if(!block){
            break;
        }

        size_t n = fread(block->data, sizeof(uint8_t), prodArgs->blockSize, f);
        block->len = n;

        // End of data in file case
        if(n == 0){
            if(feof(f)){
                rbCommitWriteSlot(prodArgs->ring, 1);
            }else{
                LOG_ERROR("Read I/O error no more byte to read");
                rbAbort(prodArgs->ring);
            }
            
            break;
        }else{
            rbCommitWriteSlot(prodArgs->ring, 0);
        }
    }
    fclose(f);
    return NULL;
}

void *consumerCall(void *args){
    consArgs_t *consArgs = (consArgs_t *)args;

    while(1){
        block_t block = rbAcquireReadSlot(consArgs->ring);

        if(block.len > 0){
            if(!writeAllFt(consArgs, block.data, block.len)){
                LOG_ERROR("Error trying to write an entire chunk of data to the FTDI device");
                rbAbort(consArgs->ring);
                return NULL;
            }
        }

        rbCommitReadSlot(consArgs->ring);

        if(consArgs->ring->abort){
            LOG_ERROR("Error aborting consumer thread routine");
            return NULL;
        }

        if(block.eof){
            printf("[INDICATION] Success writing all the data from file to FTDI device!!!!\n");
            return NULL;
        }
    }
}

void cleanUpRessources(ringBuffer_t *rb, FT_HANDLE ftHandle){
    rbFree(rb);
    FT_Close(ftHandle);
}
