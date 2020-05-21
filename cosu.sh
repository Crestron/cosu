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



source settings.cnf

# make sure our folder names don't have spaces
root_folder=$output_folder/"${ssldef_root_cn// /_}"
signer_folder=$output_folder/"${ssldef_signer_cn// /_}"
safe_device_name="${ssldef_device_hostname// /_}"

if expr "$ssldef_device_hostname" : ".*\*.*"; then
    safe_device_name="wildcard"
fi

device_folder=$output_folder/$safe_device_name
deploy_folder=$output_folder/deploy
device_deploy_folder=$deploy_folder/$safe_device_name

# Final tree looks like
# /
#    root
#    signer
#    dev1
#    dev2
#    deploy
#       dev1
#       dev2
# where the output folder has all the files in the right formats

source cosu_menu.sh
source cosu_root.sh
source cosu_signer.sh
source cosu_device_setup.sh
source cosu_device_csr.sh
source cosu_device_cert.sh
source cosu_utils.sh
source cosu_bulk.sh

run


