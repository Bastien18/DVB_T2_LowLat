#ifndef DATA_TRANSFER_H
#define DATA_TRANSFER_H

#include "ringBuffer.h"
#include "cli_utils.h"
#include "ftd2xx.h"

#define CLI_ARGUMENT_MIN 2

#define USB_IN_CHUNK_SIZE (64 * 1024)
#define USB_OUT_CHUNK_SIZE (64 * 1024)
#define USB_LATENCY_TIMER 2
#define USB_READ_TIMEOUTS 250
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
 * @brief                   Open and initialized FTDI device
 * @param ftHandle          Handler for FTDI device
 * @param ftPurge           Purge flag to choose which (TX or RX) buffer to empty inside FTDI
 * @param uIntransferSize   Transfer size for USB in request
 * @param uOutTransferSize  Transfer size for USB out request
 * @param uLatency          Required value in ms for latency timer
 * @param uReadTimeout      Read timeout value in ms
 * @param uWriteTimeout     Write timeout value in ms
 * @param uEnable           Mode value related to FTDI working mode
 * @return                  0 in case of success, 1 instead
 */
int initFt(FT_HANDLE *ftHandle, ULONG ftPurge, ULONG uInTransferSize, ULONG uOutTransferSize, ULONG uLatency, ULONG uReadTimeout, ULONG uWriteTimeout, ULONG uEnable);

/**
 * @brief                   Print error message and exit process in case of d2xx driver call
 *                          failing
 * @param msg               Message delivered to the user
 * @param ftStatus          Status code of FTDI device
 */
void dieFt(const char* msg, FT_STATUS ftStatus);

/**
 * @brief                   Start the transfer of data from .ts file to the FTDI device
 * @param ftHandle          Handler of the FTDI device
 * @param filename          .ts filename
 * @return                  0 in case of success, 1 instead
 */
int startTransferFt(FT_HANDLE ftHandle, const char *filename);

/**
 * @brief                   Write an entire chunk of TS data inside ring buffer. It garantees
 *                          that a full chunk of data is transmitted
 * @param consArgs          Structure containing argument passed to the consumer thread
 * @param buf               Buffer containing data written to the FTDI device
 * @param len               Number of data to write
 * @return                  1 if write succeed, 0 instead   
 */
int writeAllFt(consArgs_t *consArgs, uint8_t* buf, DWORD len);

/**
 * @brief                   Producer thread that read from the file specified in args
 *                          to a ring buffer also specified in args
 * @param args              Ptr to a prodArgs_t structure 
 */
void* producerCall(void * args);
/**
 * @brief                   Consumer thread that read from the ring buffer specified in args
 *                          to the FTDI device specified in args
 * @param args              Ptr to a consArgs_t structure
 */
void* consumerCall(void * args);

/**
 * @brief                   Free every ressources previously allocated
 * @param rb                Ring buffer to free
 * @param ftHandle          FTDI handler to free
 */
void cleanUpRessources(ringBuffer_t *rb, FT_HANDLE ftHandle);

#endif