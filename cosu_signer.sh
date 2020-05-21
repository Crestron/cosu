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


#########################################################################
setup_signer(){
# setup the environment for the intermediate (signer) certs
    
    if test ! -d $signer_folder; then
        mkdir $signer_folder
    fi

    if test ! -f $signer_folder/index.txt; then
        touch $signer_folder/index.txt
    fi

    if test ! -f $signer_folder/index.txt.attr; then
        touch $signer_folder/index.txt.attr
    fi

    if test ! -f $signer_folder/serial; then
        echo 1000 > $signer_folder/serial
    fi

}

################################################################################
write_signer_config(){
# setup the configuration for the intermediate certs. The policy is looser
# than the root
cat > $signer_folder/ssl.cnf << EOL
[ ca ]
default_ca = CA_default 
[CA_default] 
default_md = sha256 
database          = $signer_folder/index.txt
serial            = $signer_folder/serial
policy            = policy_loose 
[ policy_loose ] 
# The signer CA should only sign intermediate certificates that match. 
# See the POLICY FORMAT section of man ca. 
countryName             = optional 
stateOrProvinceName     = optional 
organizationName        = optional 
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
CN = $ssldef_signer_cn
#emailAddress = $ssldef_email 
[ v3_intermediate_ca ] 
# Extensions for a typical CA (man x509v3_config). 
subjectKeyIdentifier = hash 
authorityKeyIdentifier = keyid:always,issuer 
basicConstraints = critical, CA:true, pathlen:0 
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOL
}

######################################################################
view_signer_cert(){
# View the fields in a previously generated intermediate cert
openssl x509 -noout -text -in $signer_folder/cert.pem
}

#######################################################################
gen_signer(){    
# Prompts for a password and then generates the private key and cert
# then signs using the root.
    while true 
    do
        read -sp "Please enter a password for the signer key: " signer_password
        echo ""
        read -sp "Please verify the signer key password: " signer_password_verify
        echo ""
        if [ "$signer_password" == "$signer_password_verify" ] ; then
            break 
        else
            echo "Passwords don't match. Please try again."
        fi
    done
    
    pause

    setup_signer
    write_signer_config

    #set -o xtrace

    echo Generating Key...
    #openssl $sslkeygen -passout pass:$signer_password $sslkeygenparams -out $signer_folder/key.pem $sslkeygennumbits
    openssl genpkey -algorithm $keyalgorithm -pass pass:$signer_password $keygenparams -out $signer_folder/key.pem
    echo Done

    echo Create the signer CSR...
    openssl req -passin pass:$signer_password -config $signer_folder/ssl.cnf -new -$sslsha -key $signer_folder/key.pem -out $signer_folder/csr.pem

    echo Ready to sign the intermediate certificate
    read -sp "Please enter the ROOT key password" root_password

    echo Creating Certificate...
    openssl ca -batch -passin pass:$root_password -config $signer_folder/ssl.cnf -cert $root_folder/cert.pem -keyfile $root_folder/key.pem -outdir $signer_folder -extensions v3_intermediate_ca -days $sslintdays -notext -md $sslsha -in $signer_folder/csr.pem -out $signer_folder/cert.pem
    echo Done

    #set +o xtrace
    
    root_password=""
    signer_password=""
    signer_password_verify=""

    cat $signer_folder/cert.pem  $root_folder/cert.pem > $signer_folder/chain.pem

    openssl verify -CAfile $root_folder/cert.pem $signer_folder/cert.pem

    read -p "Would you like to view the certificate [y/n]: " choice
    
	case $choice in
		y) view_signer_cert ;;
		n) ;;
		*) echo -e "${RED}Error...${STD}" && sleep 2
	esac



}