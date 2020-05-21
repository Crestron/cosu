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

#############################################################
setup_root(){
# Sets up creation of the new CA environment including some
# things to make up for the odd behavior of OpenSSL
    
    if test ! -d $output_folder; then
        mkdir $output_folder
        mkdir $root_folder

    fi

    if test ! -f $root_folder/index.txt; then
        touch $root_folder/index.txt
    fi

    if test ! -f $root_folder/index.txt.attr; then
        touch $root_folder/index.txt.attr
    fi

    if test ! -f $root_folder/serial; then
        echo 1000 > $root_folder/serial
    fi

}

###############################################################
write_root_config(){
# setup the config to generate root certificates
# This will only allow you to sign intermediate certificates 
# with the same country, state/province and organization
cat > $root_folder/ssl.cnf << EOL
[ ca ]
default_ca = CA_default 
[CA_default] 
default_md = sha256 
policy            = policy_strict 
[ policy_strict ] 
# The root CA should only sign intermediate certificates that match. 
# See the POLICY FORMAT section of man ca. 
countryName             = match 
stateOrProvinceName     = match 
organizationName        = match 
organizationalUnitName  = optional 
commonName              = supplied 
emailAddress            = optional 
[ req ] 
# Options for the req tool (man req). 
prompt              = no
default_bits        = 2048 
distinguished_name  = req_distinguished_name 
string_mask         = utf8only 
[ req_distinguished_name ] 
C = $ssldef_country 
ST = $ssldef_state
L = $ssldef_locality 
O = $ssldef_org
#OU = $ssldef_org_unit 
CN = $ssldef_root_cn
#emailAddress = $ssldef_email 
[ v3_ca ] 
# Extensions for a typical CA (man x509v3_config). 
subjectKeyIdentifier = hash 
authorityKeyIdentifier = keyid:always,issuer 
basicConstraints = critical, CA:true 
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOL
}

################################################################
view_root_cert(){
# View the fields of a previously generated root certificate
openssl x509 -noout -text -in $root_folder/cert.pem
}


###############################################################
gen_root(){    
# prompts for a password for the root key and then generates 
# the key and the certifiate.

    while true 
    do
        read -sp "Please enter a password for the root key: " root_password
        echo ""
        read -sp "Please verify the root key password: " root_password_verify
        echo ""
        if [ "$root_password" == "$root_password_verify" ] ; then
            break 
        else
            echo "Passwords don't match. Please try again."
        fi
    done
    
    pause

    setup_root
    write_root_config

    echo Generating Key...
    #openssl $sslkeygen -passout pass:$root_password $sslkeygenparams -out $root_folder/key.pem $sslkeygennumbits
    openssl genpkey -algorithm $keyalgorithm -pass pass:$root_password $keygenparams -out $root_folder/key.pem


    echo Done

    echo Creating Certificate...
    openssl req -passin pass:$root_password -config $root_folder/ssl.cnf -key $root_folder/key.pem -new -x509 -days $sslrootdays -$sslsha -extensions v3_ca -out $root_folder/cert.pem
    echo Done
    
    root_password=""
    root_password_verify=""

    read -p "Would you like to view the certificate [y/n]: " choice
    
	case $choice in
		y) view_root_cert ;;
		n) ;;
		*) echo -e "${RED}Error...${STD}" && sleep 2
	esac

}