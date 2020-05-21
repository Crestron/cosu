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

#####################################################################################################
gen_bulk_device(){
# generates a set of certificates for a list of devices
# passwords are entered once and used for all devices
# The bulk_device_list file will be read and each line generates another certificate
# Probably not used too much in real life, but this handles the support for wildcard certificates as well
# The wildcard handling for the interactive method is in cosu.sh

    while true 
    do
        read -sp "Please enter the Signing key password: " signer_password
        echo ""
        read -sp "Please verify the Signing key password: " signer_password_verify
        echo ""
        if [ "$signer_password" == "$signer_password_verify" ] ; then
            break 
        else
            echo "Passwords don't match. Please try again."
        fi
    done

    while true 
    do
        read -sp "Please enter a password for the device key: " device_password
        echo ""
        read -sp "Please verify the device key password: " device_password_verify
        echo ""
        if [ "$device_password" == "$device_password_verify" ] ; then
            break 
        else
            echo "Passwords don't match. Please try again."
        fi
    done

    OLDIFS=$IFS
    IFS=','
    [ ! -f $bulk_device_list ] && { echo "$bulk_device_list file not found"; exit 99; }
    while IFS=, read -r ssldef_device_hostname ssldef_device_ip
    do
        if [[ ! $ssldef_device_hostname =~ ^[[:alpha:]] ]]; then
            break
            #echo "Empty line"
        else
            #echo "Generating certificate for $ssldef_device_hostname $ssldef_device_ip" 
            IFS=$OLDIFS
            safe_device_name="${ssldef_device_hostname// /_}"

            if expr "$ssldef_device_hostname" : ".*\*.*"; then
                safe_device_name="wildcard"
            fi

            device_folder=$output_folder/$safe_device_name
            deploy_folder=$output_folder/deploy
            device_deploy_folder=$deploy_folder/$safe_device_name
            
            
            gen_device_csr
            gen_device_cert
            IFS=','
        fi
        
    done < $bulk_device_list
    IFS=$OLDIFS

    # clear out the in-memory passwords - not exactly a wipe but 
    device_password=""
    device_password_verify=""
    signer_password=""
    signer_password_verify=""

    # we have done a lot of different things to our environment variables so they 
    # probably need to be reinitialized right now or we can just take the easy route and ...
    exit 0
    
}