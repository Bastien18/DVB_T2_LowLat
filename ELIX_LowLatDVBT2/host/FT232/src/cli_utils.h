#ifndef CLI_UTILS_H
#define CLI_UTILS_H

#include <stdbool.h>
#include <stdint.h>
#include "ftd2xx.h"

#define USER_INPUT_MAX_LEN      256
#define COMMAND_MAX_LEN         32
#define NIOS_PKT_LEN            16

#define STATUS_COMMAND_STR      "status"
#define INIT_COMMAND_STR        "init"
#define SET_COMMAND_STR         "set"
#define TX_MUTE_COMMAND_STR     "tx_mute"
#define TX_ENABLE_COMMAND_STR   "tx_enable"
#define TX_FILE_COMMAND_STR     "tx_file"
#define TX_START_COMMAND_STR    "tx_start"
#define EXIT_COMMAND_STR        "exit"
#define HELP_COMMAND_STR        "help"

#define BANDWIDTH_OPTION_STR    "bandwidth"
#define FREQUENCY_OPTION_STR    "frequency"
#define GAIN_OPTION_STR         "gain"
#define SAMPLERATE_OPTION_STR   "samplerate"
#define CHANNEL_TX_STR          "tx"
#define CHANNEL_RX_STR          "rx"

#define MAGIC_16x64_CNST        'E'

#define NO_DEVICE 1

#define WELCOME_MSG             " ____    __     ______  __   __       ____     __     ______\n" \
                                "/\\  _`\\ /\\ \\   /\\__  _\\/\\ \\ /\\ \\     /\\  _`\\  /\\ \\   /\\__  _\\    \n" \
                                "\\ \\ \\L\\_\\ \\ \\  \\/_/\\ \\/\\ `\\`\\/'/'    \\ \\ \\/\\_\\\\ \\ \\  \\/_/\\ \\/    \n" \
                                " \\ \\  _\\L\\ \\ \\  __\\ \\ \\ `\\/ > <       \\ \\ \\/_/_\\ \\ \\  __\\ \\ \\    \n"    \
                                "  \\ \\ \\L\\ \\ \\ \\L\\ \\\\_\\ \\__ \\/'/\\`\\     \\ \\ \\L\\ \\\\ \\ \\L\\ \\\\_\\ \\__ \n" \
                                "   \\ \\____/\\ \\____//\\_____\\/\\_\\\\ \\_\\    \\ \\____/ \\ \\____//\\_____\\\n"  \
                                "    \\/___/  \\/___/ \\/_____/\\/_/ \\/_/     \\/___/   \\/___/ \\/_____/  \n" \
                                "\nWelcome to ELIX CLI\n" \
                                "Type help for command description\n\n"

#define INPUT_MSG               "elixCli>"

#define HELP_MSG                "elix_cli — AD9361 RFIC control + TS burst helper (interactive)\n\
                                \n\
                                USAGE:\n\
                                  elix_cli\n\
                                  elix_cli -h | --help\n\
                                \n\
                                DESCRIPTION:\n\
                                  Interactive CLI that builds 16-byte NIOS 16x64 packets to control the RFIC\n\
                                  (AD9361 via NIOS) and prepare a TS file transfer.\n\
                                  Commands are entered at the prompt and the tool prints the resulting 16-byte\n\
                                  packet as hex bytes.\n\
                                \n\
                                PROMPT:\n\
                                  elixCli>\n\
                                \n\
                                COMMANDS:\n\
                                \n\
                                  status\n\
                                        Build an RFIC STATUS request (read).\n\
                                        Notes:\n\
                                          - Uses RFIC system channel (0x0F).\n\
                                \n\
                                  init\n\
                                        Build an RFIC INIT request (write).\n\
                                        Notes:\n\
                                          - Writes INIT=1 on RFIC system channel (0x0F).\n\
                                \n\
                                  set <option> <channel> <value>\n\
                                        Build an RFIC SET request (write).\n\
                                \n\
                                        <option> is one of:\n\
                                          bandwidth     (cmd 0x05, value parsed as uint32)\n\
                                          frequency     (cmd 0x04, value parsed as uint64)\n\
                                          gain          (cmd 0x07, value parsed as uint32)\n\
                                          samplerate    (cmd 0x03, value parsed as uint32)\n\
                                \n\
                                        <channel> is one of:\n\
                                          rx            (channel id 0x00)\n\
                                          tx            (channel id 0x01)\n\
                                \n\
                                        Examples:\n\
                                          set bandwidth tx 20000000\n\
                                          set frequency tx 915000000\n\
                                          set gain rx 30\n\
                                          set samplerate tx 30720000\n\
                                \n\
                                  tx_mute\n\
                                        Build an RFIC TXMUTE request (write).\n\
                                        Notes:\n\
                                          - Uses TX channel (0x01)\n\
                                          - Command id 0x0A\n\
                                          - No value argument (payload left at 0)\n\
                                \n\
                                  tx_enable\n\
                                        Build an RFIC ENABLE request (write) for TX.\n\
                                        Notes:\n\
                                          - Uses TX channel (0x01)\n\
                                          - Command id 0x02\n\
                                          - Writes enable=1 in payload\n\
                                \n\
                                  tx_file <path>\n\
                                        Load a TS file path and compute its size.\n\
                                        Effects:\n\
                                          - Stores <path> internally\n\
                                          - Sets stored size = file size in bytes (ftell)\n\
                                        Notes:\n\
                                          - This command does NOT build an RFIC packet.\n\
                                          - Prints a warning if the file size is 0.\n\
                                \n\
                                        Example:\n\
                                          tx_file stream.ts\n\
                                \n\
                                  tx_start\n\
                                        Build an ENTER_DATA packet (write) using the last tx_file size.\n\
                                        Notes:\n\
                                          - Uses target id 0x80 (user target)\n\
                                          - Uses address 0x0001\n\
                                          - Encodes DATA = stored tsSize as uint64 payload\n\
                                \n\
                                        Typical flow:\n\
                                          tx_file stream.ts\n\
                                          tx_start\n\
                                \n\
                                  exit\n\
                                        Exit the application immediately.\n\
                                \n\
                                NOTES / CURRENT LIMITATIONS:\n\
                                  - Unknown commands print: \"Uknown command ...\" and return an error.\n\
                                  - This CLI currently prints the 16-byte packet but does not send it to hardware.\n\
                                  - tx_start uses the most recent size set by tx_file; if tx_file was not run,\n\
                                    the size may be uninitialized.\n\
                                \n\
                                EXAMPLE SESSION:\n\
                                  elixCli> init\n\
                                  elixCli> set frequency tx 915000000\n\
                                  elixCli> set samplerate tx 30720000\n\
                                  elixCli> tx_enable\n\
                                  elixCli> tx_file test.ts\n\
                                  elixCli> tx_start\n\
                                  elixCli> exit\n"

#define LOG_ERROR(msg, ...) (fprintf(stderr, \
                              "[ERROR] In function: %s\n" \
                              "Description: " msg "\n", __func__ __VA_OPT__(,) __VA_ARGS__))

typedef struct{
    bool deviceIsInit;
    bool txIsEnable;
    bool deviceIsTx;
    FT_HANDLE *ftHandle;
}cliState_t;

typedef struct{
    char filename[USER_INPUT_MAX_LEN];
    uint64_t tsSize;
}txInfo_t;

/**
 * @brief               Display welcome message to CLI end user
 */
void displayWelcome();

/**
 * @brief               Handler function when user enter status command
 * @param RFICCmd       Ptr to the RFIC to send to FTDI
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int statusHandler(const char *RFICCmd, cliState_t *state);

/**
 * @brief               Handler function when user enter init command
 * @param RFICCmd       Ptr to the RFIC to send to FTDI
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int initHandler(const char *RFICCmd, cliState_t *state);

/**
 * @brief               Parse a set command with the different options and channel and 
 *                      converts it into corresponding RFIC 16x64 packet
 * @param option        String of corresponding option to set
 * @param channel       String of corresponding channel to set (TX/RX)
 * @param value         String of value to set for corresponding option and channel
 * @param RFICCmd       Output parameter to RFIC 16x64 packet char array[16]
 * @param state         Actual state of the cli application 
 * @return              0 in case of success, 1 instead
 */
int setHandler(char *option, char *channel, char *value, char *RFICCmd, cliState_t *state);

/**
 * @brief               Handler function when user enter tx_mute command
 * @param RFICCmd       Ptr to the RFIC to send to FTDI
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int txmuteHandler(const char *RFICCmd, cliState_t *state);

/**
 * @brief               Handler function when user enter tx_enable command
 * @param RFICCmd       Ptr to the RFIC to send to FTDI
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int txenableHandler(const char *RFICCmd, cliState_t *state);

/**
 * @brief               Handler function when user enter tx_start command
 * @param RFICCmd       Ptr to the RFIC to send to FTDI
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int txstartHandler(const char *RFICCmd, cliState_t *state, txInfo_t *txInfo);

/**
 * @brief               Parse every command to determine which kind of command it is.
 *                      Proceed to handle it as intended afterward
 * @param userInput     User input string
 * @param RFICCmd       Output parameter to RFIC 16x64 packet char array[16]
 * @param txInfo        Output parameter to .ts file informations
 * @param state         Ptr to current cli state structure
 * @return              0 in case of success, 1 instead
 */
int parseArg(char *userInput, char *RFICCmd, txInfo_t *txInfo, cliState_t *state);

/**
 * @brief                 Write a 16bytes packet to FTDI and wait for another
 *                        16bytes packet response from FTDI device
 * @param ftHandle        FTDI device related structure
 * @param tx              16bytes array to send to FTDI
 * @param rx              16bytes address to write FTDI response
 * @param expectedMagic   Check magic constant in FTDI response if matches arg
 *                        If 0 is passed as argument no check is applied
 * @param requireSuccess  If true check if response raised success flag if not
 *                        it'll log an error
 * @return                0 in case of success, 1 instead
 */
int ftdiXferNios(FT_HANDLE ftHandle, const char *tx, char *rx, char expectedMagic, int requireSuccess);

/**
 * @brief                 Ask CLI end user for a command and parse it afterward.
 * @return                0 in case of success, 1 instead
 */
int userInput();

#endif