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


##############################################################################################
write_device_cert_config(){
# This method writes out the ssl.cnf used for generating a device certificate
# some inportant points are basicConstraints is set to FALSE so that this is not a signing cert
# we use a looser policy regarding the types of certificates that we can generate.
# The other important part is the Subject Alt Name (SAN) is written out for the device as well
cat > $device_folder/ssl.cnf << EOL
[ ca ]
default_ca = CA_default 
[CA_default] 
default_md = $sslsha 
database          = $signer_folder/index.txt
serial            = $signer_folder/serial
policy            = policy_loose 
[ policy_loose ] 
# Allow the intermediate CA to sign a more diverse range of certificates
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
CN = $ssldef_device_hostname
#emailAddress = $ssldef_email 
[server_cert] 
# Extensions for server certs(man x509v3_config). 
subjectKeyIdentifier = hash 
authorityKeyIdentifier = keyid:always,issuer 
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
extendedKeyUsage = serverAuth
EOL

if valid_ip $ssldef_device_ip; then 
    cat >> $device_folder/ssl.cnf << EOL
subjectAltName = DNS:$ssldef_device_hostname, IP:$ssldef_device_ip
EOL
    else
    cat >> $device_folder/ssl.cnf << EOL
subjectAltName = DNS:$ssldef_device_hostname
EOL
fi

}

##############################################################################################
view_device_cert(){
# Allows you to view all the fields in the certificate
openssl x509 -noout -text -in $device_folder/cert.pem
}

##############################################################################################
copy_output(){
# Take the output and put it in the proper folder to make it easier to deploy the certs
# This includes all the various formats and instructions for device types
    echo "Now copying files for Crestron Device Deployment"

    if test ! -d $deploy_folder; then 
        mkdir $deploy_folder
    fi

    if test ! -d $device_deploy_folder; then
        mkdir $device_deploy_folder
    fi




    # copy and rename the root certificate
    cp $root_folder/cert.pem $device_deploy_folder/rootCA_cert.cer

    #copy and rename the signer certificate
    cp $signer_folder/cert.pem $device_deploy_folder/intermediate_cert.cer

    #copy and rename the device certificate
    cp $device_folder/cert.pem $device_deploy_folder/srv_cert.cer

    #copy the certificate chain
    cp $signer_folder/chain.pem $device_deploy_folder/chain.cer

    #unencrypt and rename the private key
    openssl rsa -passin pass:$device_password -in $device_folder/key.pem -out $device_deploy_folder/srv_key.pem

    #create a PFX File
    openssl pkcs12 -export -passin pass:$device_password -passout pass:$device_password -out $device_deploy_folder/webserver_cert.pfx -inkey $device_folder/key.pem -in $device_folder/cert.pem
   
    #write out the user instructions
    cat > $device_deploy_folder/readme.txt << EOL

rootCA_cert.cer may be added to your local certificate store as a trusted certificate

**********************************************
***** 3 Series Instructions
**********************************************
Please place chain.cer, srv_cert.cer and srv_key.pem
into the control system \User folder using SFTP

Execute the following commands

>del \sys\rootCA_cert.cer
>del \sys\srv_cert.cer
>del \sys\srv_key.pem
>move User\chain.cer \sys\rootCA_cert.cer
>move User\srv_cert.cer \sys
>move User\srv_key.pem \sys

>ssl ca 

**********************************************
***** 4 Series Instructions
**********************************************
Please place rootCA_cert.cer, intermediate_cert.cer, srv_cert.cer and srv_key.pem
into the control system \Sys folder using SFTP

Execute the following commands

>move User\intermediate_cert.cer \romdisk\user\cert

>certificate add intermediate
>ssl ca 


**********************************************
***** Other Devices (4 Series, NVX, TSW, etc)
**********************************************
Please place rootCA_cert.cer, intermediate_cert.cer, webserver_cert.pfx
into the /User/Cert folder using SFTP (first remove any root_cert.cer that might be present)

>move /User/Cert/rootCA_cert.cer /User/Cert/root_cert.cer
>certificate add root
>certificate add intermediate
>certificate add webserver <password>
>ssl ca 

EOL
  
}


#######################################################################################################
gen_device_cert(){    
# Creates a certificate based on the various environment variables and copies to the output folder
# assumes we already have a CSR as well
    setup_device
    write_device_cert_config
   
    echo "Creating Certificate..."
    openssl ca -batch -passin pass:$signer_password -config $device_folder/ssl.cnf -cert $signer_folder/cert.pem -keyfile $signer_folder/key.pem -outdir $device_folder -extensions server_cert -days $sslsrvdays -notext -md $sslsha -in $device_folder/csr.pem -out $device_folder/cert.pem
    echo "Done"
    
    copy_output

}


#######################################################################################################
interactive_gen_device_cert(){
# Creates a certificate based on the various environment variables and copies to the output folder
# This allows you to enter the signing key password and generate the certificate
    
    echo Ready to sign the device certificate
    read -sp "Please enter the Signing key password: " signer_password

    gen_device_cert

    signer_password=""
   
    openssl verify -CAfile $signer_folder/chain.pem $device_folder/cert.pem

    read -p "Would you like to view the certificate [y/n]: " choice
    
	case $choice in
		y) view_device_cert ;;
		n) ;;
		*) echo -e "${RED}Error...${STD}" && sleep 2
	esac  

}