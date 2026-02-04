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

 #include "data_transfer.h"
 #include "ringBuffer.h"
 #include "cli_utils.h"

//-------------------------------------------------------------------------------------
//                                  MAIN
//-------------------------------------------------------------------------------------
int main(int argc, char **argv){

    displayWelcome();

    userInput();
}

