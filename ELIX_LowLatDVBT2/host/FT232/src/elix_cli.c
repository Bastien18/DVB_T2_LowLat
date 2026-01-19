/**
 * File: elix_cli.c
 * Author: Bastien Pillonel
 * Email: bastien.pillonel@heig-vd.ch
 * 
 * Description: This application lets user stream a simple .ts file to Elix LowLat DVBT2 board.
 *              Additional features like configuring RF transciever (AD9361), handling other type
 *              of input files, etc... could be implemented in future patches.
 * 
 */

#include "ftd2xx.h"
#include <stdio.h>
#include <pthread.h>
#include "ringBuffer.h"

#define CLI_ARGUMENT_MIN 2

#define USB_IN_CHUNK_SIZE (64 * 1024)
#define USB_OUT_CHUNK_SIZE (64 * 1024)
#define USB_LATENCY_TIMER 2
#define USB_READ_TIMEOUTS 0
#define USB_WRITE_TIMEOUTS 5000
#define USB_SYNC_FIFO_BITMODE 0x40

#define RING_BUFFER_CAPACITY 128 
#define RING_BUFFER_BLOCK_SIZE (64 * 1024)

typedef struct{
    ringBuffer_t *ring;
    const char* filename;
    size_t blockSize;
}prodArgs_t;

typedef struct{
    ringBuffer_t *ring;
    FT_HANDLE ftHandle;
}consArgs_t;

/**
 * @brief           Print error message and exit process in case of d2xx driver call
 *                  failing
 * @param msg       Message delivered to the user
 * @param ftStatus  Status code of FTDI device
 */
void dieFt(const char* msg, FT_STATUS ftStatus);
/**
 * @brief           Write an entire chunk of TS data inside ring buffer. It garantees
 *                  that a full chunk of data is transmitted
 * @param consArgs  Structure containing argument passed to the consumer thread
 * @param buf       Buffer containing data written to the FTDI device
 * @param len       Number of data to write
 * @return          1 if write succeed, 0 instead   
 */
int writeAllFt(consArgs_t *consArgs, uint8_t* buf, DWORD len);

/**
 * @brief           Producer thread that read from the file specified in args
 *                  to a ring buffer also specified in args
 * @param args      Ptr to a prodArgs_t structure 
 */
void* producerCall(void * args);
/**
 * @brief           Consumer thread that read from the ring buffer specified in args
 *                  to the FTDI device specified in args
 * @param args      Ptr to a consArgs_t structure
 */
void* consumerCall(void * args);

//-------------------------------------------------------------------------------------
//                                  MAIN
//-------------------------------------------------------------------------------------
int main(int argc, char **argv){
    // Handling cli application argument count
    if(argc < CLI_ARGUMENT_MIN){
        fprintf(stderr, "Usage: %s <file.ts>\n", argv[0]);
        return 1;
    }

    // Handling FTDI device initialisation
    FT_HANDLE ftHandle = NULL;
    FT_STATUS ftStatus;

    ftStatus = FT_Open(0, &ftHandle);
    if(ftStatus != FT_OK){
        dieFt("FT_Open failed", ftStatus);
    }

    // Clean init with reset and purge (is optional)
    ftStatus = FT_ResetDevice(ftHandle);
    if(ftStatus != FT_OK){
        dieFt("FT_ResetDevice failed", ftStatus);
    }

    ftStatus = FT_Purge(ftHandle, FT_PURGE_RX | FT_PURGE_TX);
    if(ftStatus != FT_OK){
        dieFt("FT_Purge failed", ftStatus);
    }

    // Throughput related tunning
    ftStatus = FT_SetUSBParameters(ftHandle, USB_IN_CHUNK_SIZE, USB_OUT_CHUNK_SIZE);
    if(ftStatus != FT_OK){
        dieFt("FT_SetUSBParameters failed", ftStatus);
    }

    ftStatus = FT_SetLatencyTimer(ftHandle, USB_LATENCY_TIMER);
    if(ftStatus != FT_OK){
        dieFt("FT_SetLatencyTimer failed", ftStatus);
    }

    ftStatus = FT_SetTimeouts(ftHandle, USB_READ_TIMEOUTS, USB_WRITE_TIMEOUTS);
    if(ftStatus != FT_OK){
        dieFt("FT_SetTimeouts failed", ftStatus);
    }

    // Set bitmode 0x40 for Sync FIFO application 
    ftStatus = FT_SetBitMode(ftHandle, 0xff, USB_SYNC_FIFO_BITMODE);
    if(ftStatus != FT_OK){
        dieFt("FT_SetBitMode failed", ftStatus);
    }

    // Initialize ring buffer for TS data
    ringBuffer_t rBuffer;
    rbInit(&rBuffer, RING_BUFFER_CAPACITY, RING_BUFFER_BLOCK_SIZE);

    // Initialize consumer and producer thread
    pthread_t consumerThread;
    pthread_t producerThread;

    consArgs_t consArgs = {.ftHandle = ftHandle, .ring = &rBuffer};
    prodArgs_t prodArgs = {.blockSize = RING_BUFFER_BLOCK_SIZE, .filename = argv[1], .ring = &rBuffer};

    pthread_create(&consumerThread, NULL, consumerCall, (void *)&consArgs);
    pthread_create(&producerThread, NULL, producerCall, (void *)&prodArgs);

    // Waiting for both threads to end
    pthread_join(consumerThread, NULL);
    pthread_join(producerThread, NULL);

    // Clean up resources
    rbFree(&rBuffer);
    return 0;
}

void dieFt(const char* msg, FT_STATUS ftStatus){
    fprintf(stderr, "%s (FT_Status=%d)\n", msg, (int)ftStatus);
    exit(1);
}

int writeAllFt(consArgs_t *consArgs, uint8_t* buf, DWORD len){
    DWORD offset = 0;
    while(offset < len){
        DWORD written = 0;
        FT_STATUS ftStatus = FT_Write(consArgs->ftHandle, buf + offset, len - offset, &written);

        if(ftStatus != FT_OK){
            fprintf(stderr, "FT_Write failed: %d\n", ftStatus);
            return 0;
        }

        if(!written){
            // Check for a stall from FTDI device. Add a sleep call to avoid tight infinite loop
            printf("[WARNING]FT_Write() operation wrote 0byte. Check for anormal stall from FTDI\n");
            Sleep(1);
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
        fprintf(stderr, "Something went wrong opening file %s\n", prodArgs->filename);
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
            rbCommitWriteSlot(prodArgs->ring, 1);
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
        block_t block = rbPop(consArgs->ring);

        if(block.len > 0){
            if(!writeAllFt(consArgs, block.data, block.len)){
                fprintf(stderr, "Error trying to write an entire chunk of data to the FTDI device\n");
                return NULL;
            }
        }

        if(block.eof){
            printf("[INDICATION] Success writing all the data from file to FTDI device!!!!\n");
            return NULL;
        }
    }
}
