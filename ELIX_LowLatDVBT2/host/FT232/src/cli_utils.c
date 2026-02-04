/**
 * File: cli_utils.c
 * Author: Bastien Pillonel
 * Email: bastien.pillonel@heig-vd.ch
 * 
 * Description: This file implement tools to handle a Command Line Interface with the end user.
 *              The end user will be able to configure AD9361 settings, set .ts file from where 
 *              data will be pulled out to be transfered to the cms0041 core and start and top the 
 *              transmission.
 * 
 */

#include "cli_utils.h"
#include "data_transfer.h"
#include <stdio.h>
#include <string.h>
#include <inttypes.h>

void displayWelcome(){
    printf(WELCOME_MSG);
}

void unsigned32ToLittleEndian(uint32_t value, char *destBuffer){
    for(size_t i = 0; i < sizeof(uint32_t); ++i){
        destBuffer[i] = (value >> (i * 8)) & 0xff;
    }
}

void unsigned64ToLittleEndian(uint64_t value, char *destBuffer){
    for(size_t i = 0; i < sizeof(uint64_t); ++i){
        destBuffer[i] = (value >> (i * 8)) & 0xff;
    }
}

// TODO clear pre initialized rx packet and uncomment the call to ftdiXferNios
int statusHandler(const char *RFICCmd, cliState_t *state){
    if(state->deviceIsTx){
        LOG_ERROR("Can't send CTRL command when host is streaming");
        return 1;
    }

    #ifndef NO_DEVICE
        char rx[16];

        if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
            return 1;
        }
    #else
        char rx[16] = {0,0,0,0,0,0,0x05, 0x02, 0x01,0,0,0,0,0,0,0};
    #endif

    printf("\n%-17s [ STATUS ]\n\n", "");
    printf("%-35s [%s]\n", "RFIC", (rx[6] & 0x01 ? "Initialized" : "Not initialized"));
    printf("%-35s [%s]\n", "RX", (rx[6] & 0x02 ? "Enabled" : "Disabled"));
    printf("%-35s [%s]\n", "TX", (rx[6] & 0x04 ? "Enabled" : "Disabled"));
    printf("%-35s [%s]\n", "AD9361 PLL", (rx[6] & 0x08 ? "Locked" : "Unlocked"));
    printf("%-35s [%s]\n", "BBPLL", (rx[6] & 0x10 ? "Locked" : "Unlocked"));
    printf("%-35s [%s]\n", "Tracking calibration", (rx[6] & 0x20 ? "Enabled" : "Disabled"));
    printf("%-35s [0x%02hhx]\n", "RFIC error flags", rx[7]);
    printf("%-35s [%u]\n", "Current RFIC cmd in queue", rx[8]);
    printf("%-35s [%u]\n", "Last command result", rx[9]);

    return 0;
}

// Don't need to do much in there
int initHandler(const char *RFICCmd, cliState_t *state){
    char rx[16];

    if(state->deviceIsTx){
        LOG_ERROR("Can't send CTRL command when host is streaming");
        return 1;
    }

    #ifndef NO_DEVICE
        if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
            return 1;
        }
    #endif

    state->deviceIsInit = true;
    return 0;
}

int setHandler(char *option, char *channel, char *value, char *RFICCmd, cliState_t *state){
    char rx[16];

    if(state->deviceIsTx){
        LOG_ERROR("Can't send CTRL command when host is streaming");
        return 1;
    }

    if (!option || !channel || !value){
        LOG_ERROR("Invalid set command format");
        return 1;
    }

    if(!strcmp(option, BANDWIDTH_OPTION_STR)){
        // Specify bandwidth as command option
        RFICCmd[4] = 0x05;

        // Specify value for set bandwidth
        uint32_t bandwidthValue;
        if(sscanf(value, "%"SCNu32, &bandwidthValue) == 1){
            unsigned32ToLittleEndian(bandwidthValue, RFICCmd + 6);
        }else{
            LOG_ERROR("Invalid value to set bandwidth");
            return 1;
        }

    }else if(!strcmp(option, FREQUENCY_OPTION_STR)){
        // Specify frequency as command option
        RFICCmd[4] = 0x04;

        // Specify value for set frequency
        uint64_t frequencyValue;
        if(sscanf(value, "%"SCNu64, &frequencyValue) == 1){
            unsigned64ToLittleEndian(frequencyValue, RFICCmd + 6);
        }else{
            LOG_ERROR("Invalid value to set frequency");
            return 1;
        }

    }else if(!strcmp(option, GAIN_OPTION_STR)){
        // Specify gain as command option
        RFICCmd[4] = 0x07;

        // Specify value for set gain
        uint32_t gainValue;
        if(sscanf(value, "%"SCNu32, &gainValue) == 1){
            unsigned32ToLittleEndian(gainValue, RFICCmd + 6);
        }else{
            LOG_ERROR("Invalid value to set gain");
            return 1;
        }
    }else if(!strcmp(option, SAMPLERATE_OPTION_STR)){
        // Specify samplerate as command option
        RFICCmd[4] = 0x03;

        // Specify value for set gain
        uint32_t samplerateValue;
        if(sscanf(value, "%"SCNu32, &samplerateValue) == 1){
            unsigned32ToLittleEndian(samplerateValue, RFICCmd + 6);
        }else{
            LOG_ERROR("Invalid value to set samplerate");
            return 1;
        }
    }else{
        LOG_ERROR("Invalid option name for set command");
        return 1;
    }

    if(!strcmp(channel, CHANNEL_RX_STR)){
        RFICCmd[5] = 0x00;
    }else if(!strcmp(channel, CHANNEL_TX_STR)){
        RFICCmd[5] = 0x01;
    }else{
        LOG_ERROR("Invalid channel name for set command");
        return 1;
    }

    // Send set command to FTDI
    #ifndef NO_DEVICE
        if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
            return 1;
        }
    #endif

    return 0;
}

int txmuteHandler(const char *RFICCmd, cliState_t *state){
    char rx[16];

    if(state->deviceIsTx){
        LOG_ERROR("Can't send CTRL command when host is streaming");
        return 1;
    }

    #ifndef NO_DEVICE
        if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
            return 1;
        }
    #endif

    return 0;
}

int txenableHandler(const char *RFICCmd, cliState_t *state){
    char rx[16];

    if(state->deviceIsTx){
        LOG_ERROR("Can't send CTRL command when host is streaming");
        return 1;
    }

    #ifndef NO_DEVICE
        if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
            return 1;
        }
    #endif

    state->txIsEnable = true;
    return 0;
}

int txstartHandler(const char *RFICCmd, cliState_t *state, txInfo_t *txInfo){
    char rx[16];

    if(txInfo->filename[0] == '\0'){
        LOG_ERROR("No file configured for TX operation");
        return 1;
    }

    // Check if device is init and tx enable
    if(state->deviceIsInit && state->txIsEnable && !state->deviceIsTx){
        state->deviceIsTx = true;

        #ifndef NO_DEVICE
            if(ftdiXferNios(*state->ftHandle, RFICCmd, rx, MAGIC_16x64_CNST, 1)){
                return 1;
            }   
            
            if(startTransferFt(*state->ftHandle, txInfo->filename)){
                state->deviceIsTx = false;
                return 1;
            }
        #endif

    }else{
        LOG_ERROR("Can't transfer data when FTDI device is not initialized or TX is disabled or host is already transfering data");
        return 1;
    }

    state->deviceIsTx = false;
    return 0;
}

void cliStateInit(cliState_t *cliState, FT_HANDLE *ftHandle){
    cliState->deviceIsInit = false;
    cliState->txIsEnable = false;
    cliState->deviceIsTx = false;
    cliState->ftHandle = ftHandle;
}

int parseArg(char *userInput, char *RFICCmd, txInfo_t *txInfo, cliState_t *state){
    char *command;
    command = strtok(userInput, " ");

    // Set MAGIC const => 16x64 pkt format, set target ID => RFIC
    RFICCmd[0] = 0x45;
    RFICCmd[1] = 0x01;
    
    // Status command
    if(!strcmp(command, STATUS_COMMAND_STR)){
        RFICCmd[5] = 0x0F;
        if(statusHandler(RFICCmd, state)){
            return 1;
        }
    }
    // Init command
    else if(!strcmp(command, INIT_COMMAND_STR)){
        RFICCmd[2] = 0x01;
        RFICCmd[4] = 0x01;
        RFICCmd[5] = 0x0F;
        RFICCmd[6] = 0x01;

        if(initHandler(RFICCmd, state)){
            return 1;
        }
    }
    // Set command
    else if(!strcmp(command, SET_COMMAND_STR)){
        char *option = strtok(NULL, " ");
        char *channel = strtok(NULL, " ");
        char *value = strtok(NULL, " ");

        RFICCmd[2] = 0x01;
        
        if(setHandler(option, channel, value, RFICCmd, state)){
            return 1;
        }
    }
    // Tx_mute command
    else if(!strcmp(command, TX_MUTE_COMMAND_STR)){
        RFICCmd[2] = 0x01;
        RFICCmd[4] = 0x0A;
        RFICCmd[5] = 0x01;

        if(txmuteHandler(RFICCmd, state)){
            return 1;
        }
    }
    // Tx_enable command
    else if(!strcmp(command, TX_ENABLE_COMMAND_STR)){
        RFICCmd[2] = 0x01;
        RFICCmd[4] = 0x02;
        RFICCmd[5] = 0x01;
        RFICCmd[6] = 0x01;

        if(txenableHandler(RFICCmd, state)){
            return 1;
        }
    }
    // Tx_file command
    else if(!strcmp(command, TX_FILE_COMMAND_STR)){
        char *filename = strtok(NULL, " ");
        if(!filename){
            LOG_ERROR("Invalid given tx filename");
            return 1;
        }
        // Copy filename inside txInfo
        printf("Filename set is %s\n", filename);
        strcpy(txInfo->filename, filename);

        // Copy file size inside txInfo
        FILE *fp = fopen(filename, "rb");
        if(!fp){
            LOG_ERROR("Can't open file");
            return 1;
        }
        fseek(fp, 0L, SEEK_END);
        txInfo->tsSize = ftell(fp);
        fclose(fp);

        printf("File size is %u\n", txInfo->tsSize);

        if(!txInfo->tsSize){
            printf("[WARNING] Given file is empty\n");
        }

        // Directly return to caller since no interaction with FTDI device is needed
        return 0;
    }
    // Tx_start command
    else if(!strcmp(command, TX_START_COMMAND_STR)){
        RFICCmd[1] = 0x80;
        RFICCmd[2] = 0x01;
        RFICCmd[4] = 0x01;

        unsigned64ToLittleEndian(txInfo->tsSize, RFICCmd + 6);

        if(txstartHandler(RFICCmd, state, txInfo)){
            return 1;
        }
    }
    // Help command
    else if(!strcmp(command, HELP_COMMAND_STR)){
        printf(HELP_MSG);

        // Directly return to caller since no interaction with FTDI device is needed
        return 0;
    }
    // Exit command
    else if(!strcmp(command,EXIT_COMMAND_STR)){
        exit(0);
    }
    else{
        LOG_ERROR("Uknown command %s\n", userInput);
        return 1;
    }

    return 0;
}

int ftdiXferNios(FT_HANDLE ftHandle, const char *tx, char *rx, char expectedMagic, int requireSuccess){
    if(!tx || !rx){
        LOG_ERROR("TX or RX buffer are NULL pointer");
        return 1;
    }

    DWORD totalWritten = 0;
    while(totalWritten < NIOS_PKT_LEN){
        DWORD written = 0;
        FT_STATUS ftStatus = FT_Write(ftHandle, (void *)(tx + totalWritten), NIOS_PKT_LEN - totalWritten, &written);
        
        if(ftStatus != FT_OK){
            
            LOG_ERROR("FT_Write failed status= %d\n", ftStatus);
            return 1;
        }

        if(!written){
            LOG_ERROR("FT_Write wrote 0 bytes status=%d", ftStatus);
            return 1;
        }

        totalWritten +=written;
    }

    DWORD totalRead = 0;

    while(totalRead < NIOS_PKT_LEN){
        DWORD read = 0;
        FT_STATUS ftStatus = FT_Read(ftHandle, (void *)(rx + totalRead), NIOS_PKT_LEN - totalRead, &read);

        if(ftStatus != FT_OK){
            LOG_ERROR("FT_Read failed status= %d", ftStatus);
            return 1;
        }

        if(!read){
            LOG_ERROR("FT_Read read 0 bytes status=%d", ftStatus);
            return 1;
        }

        totalRead += read;
    }

    if(expectedMagic && rx[0] != expectedMagic){
        LOG_ERROR("Bad response magic: got 0x%02x expected 0x%02x\n", rx[0], expectedMagic);
        return 1;
    }

    if(requireSuccess && !(rx[2] & (1 << 1))){
        LOG_ERROR("Response missing success flag");
        return 1;
    }

    return 0;
}

int userInput(){
    char input[USER_INPUT_MAX_LEN];
    char RFICCmd[16] = {0};
    txInfo_t txInfo = {.tsSize = 0};
    txInfo.filename[0] = '\0';
    cliState_t state;
    FT_HANDLE ftHandle = NULL;

    cliStateInit(&state, &ftHandle);

    #ifndef NO_DEVICE
        if(initFt(&ftHandle, (FT_PURGE_RX | FT_PURGE_TX), USB_IN_CHUNK_SIZE, USB_OUT_CHUNK_SIZE, USB_LATENCY_TIMER, USB_READ_TIMEOUTS, USB_WRITE_TIMEOUTS, USB_SYNC_FIFO_BITMODE)){
            return 1;
        } 
    #endif

    while(1){
        printf(INPUT_MSG);
        if (!fgets(input, sizeof(input), stdin)) {
            LOG_ERROR("Invalid user input");
            return 1;
        }
        input[strcspn(input, "\r\n")] = 0;
        
        parseArg(input, RFICCmd, &txInfo, &state);

        printf("RFIC cmd is : ");

        for(size_t i = 0; i < 16; ++i){
            printf("\\%02hhx ", (unsigned char)RFICCmd[i]);
        }
        printf("\n");
    }
}

