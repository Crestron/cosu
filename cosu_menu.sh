####################################################################################
# Copyright (c) 2019 - Present Crestron Electronics, Inc.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
####################################################################################


#!/bin/bash
# A menu driven shell script sample template 
## ----------------------------------
# Step #1: Define variables
# ----------------------------------
EDITOR=vim
PASSWD=/etc/passwd
RED='\033[0;41;30m'
STD='\033[0;0;39m'
 
# ----------------------------------
# Step #2: User defined function
# ----------------------------------
pause(){
  read -p "Press [Enter] key to continue..." fackEnterKey
}

 
# function to display menus
show_menus() {
	if ! $debug; then
		clear
	fi
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~"	
	echo " Crestron OpenSSL Utility"
	echo "~~~~~~~~~~~~~~~~~~~~~~~~~"
	echo "1. Create New Root Certificate"
	echo "2. Create New Intermediate Certificate"
	echo "3. Create CSR"
	echo "4. Create Certficate from CSR"
	echo "5. Create Certificates from list of hostnames/IPs"
	echo "d. Turn Debug On/Off"
	echo "x. Exit"
}
# read input from the keyboard and take a action
# invoke the one() when the user select 1 from the menu option.
# invoke the two() when the user select 2 from the menu option.
# Exit when user the user select 3 form the menu option.
read_options(){
	local choice
	read -p "Enter choice: " choice
	case $choice in
		1) gen_root ;;
		2) gen_signer ;;
		3) interactive_gen_device_csr ;;
		4) interactive_gen_device_cert ;;
		5) gen_bulk_device ;;
		d) toggle_debug ;;
		x) exit 0;;
		*) echo -e "${RED}Error...${STD}" && sleep 1
	esac
}
 
run(){
	# ----------------------------------------------
	# Step #3: Trap CTRL+C, CTRL+Z and quit singles
	# ----------------------------------------------
	trap '' SIGINT SIGQUIT SIGTSTP
	
	# -----------------------------------
	# Step #4: Main logic - infinite loop
	# ------------------------------------
	while true
	do
	
		show_menus
		read_options
		pause
	done
}
