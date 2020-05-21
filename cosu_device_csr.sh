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

########################################################################################
view_device_csr(){
# Allows you to view all the fields in the certificate
openssl req -text -noout -verify -in $device_folder/csr.pem

}


########################################################################################
write_device_csr_config(){
# This method writes out the ssl.cnf used for generating a csr
# Not a lot special here other than copying the names
cat > $device_folder/ssl.cnf << EOL
[ ca ] 
default_ca = CA_default 
[CA_default] 
default_md = $sslsha 
[ req ] 
# Options for the req tool (man req). 
default_bits        = 2048 
distinguished_name  = req_distinguished_name 
string_mask         = utf8only 
prompt              = no
[ req_distinguished_name ] 
# See https://en.wikipedia.org/wiki/Certificate_signing_request 
C = $ssldef_country 
ST = $ssldef_state
L = $ssldef_locality 
O = $ssldef_org
#OU = $ssldef_org_unit 
CN = $ssldef_device_hostname
#emailAddress = $ssldef_email 
EOL
}

##########################################################################################
gen_device_csr(){
# assumes the password to use for the private key has already been entered
# generates the csr and private key

    setup_device
    write_device_csr_config

    #generate the key
    openssl genpkey -algorithm $keyalgorithm -pass pass:$device_password $keygenparams -out $device_folder/key.pem
 
    #echo Now Creating CSR
    openssl req -passin pass:$device_password -config $device_folder/ssl.cnf -key $device_folder/key.pem -new -$sslsha -out $device_folder/csr.pem

}

##########################################################################################
interactive_gen_device_csr(){
# allows you to type in the password for this particular private key
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

    gen_device_csr

    device_password=""
    device_password_verify=""

    read -p "Would you like to view the csr [y/n]: " choice
    
	case $choice in
		y) view_device_csr ;;
		n) ;;
		*) echo -e "${RED}Error...${STD}" && sleep 2
	esac


}
