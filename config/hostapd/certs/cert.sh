#!/bin/bash
<< END

touch index.txt
echo '01' > serial

echo "openssl dhparam -out dh 1024"
openssl dhparam -out dh 1024

echo "openssl req -new  -out server.csr -keyout server.key -config ./server.cnf"
openssl req -new  -out server.csr -keyout server.key -config ./server.cnf

echo "openssl req -new -x509 -keyout ca.key -out ca.pem -days \`grep default_days ca.cnf | sed 's/.*=//;s/^ *//'\` -config ./ca.cnf"
openssl req -new -x509 -keyout ca.key -out ca.pem -days `grep default_days ca.cnf | sed 's/.*=//;s/^ *//'` -config ./ca.cnf

echo "openssl ca -batch -keyfile ca.key -cert ca.pem -in server.csr  -key \`grep output_password ca.cnf | sed 's/.*=//;s/^ *//'\` -out server.crt -extensions xpserver_ext -extfile xpextensions -config ./server.cnf"
openssl ca -batch -keyfile ca.key -cert ca.pem -in server.csr  -key `grep output_password ca.cnf | sed 's/.*=//;s/^ *//'` -out server.crt -extensions xpserver_ext -extfile xpextensions -config ./server.cnf

echo "openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12  -passin pass:\`grep output_password server.cnf | sed 's/.*=//;s/^ *//'\` -passout pass:\`grep output_password server.cnf | sed 's/.*=//;s/^ *//'\`"
openssl pkcs12 -export -in server.crt -inkey server.key -out server.p12  -passin pass:`grep output_password server.cnf | sed 's/.*=//;s/^ *//'` -passout pass:`grep output_password server.cnf | sed 's/.*=//;s/^ *//'`

echo "openssl pkcs12 -in server.p12 -out server.pem -passin pass:\`grep output_password server.cnf | sed 's/.*=//;s/^ *//'\` -passout pass:\`grep output_password server.cnf | sed 's/.*=//;s/^ *//'\`"
openssl pkcs12 -in server.p12 -out server.pem -passin pass:`grep output_password server.cnf | sed 's/.*=//;s/^ *//'` -passout pass:`grep output_password server.cnf | sed 's/.*=//;s/^ *//'`

echo "openssl verify -CAfile ca.pem server.pem"
openssl verify -CAfile ca.pem server.pem

END
echo "openssl x509 -inform PEM -outform DER -in ca.pem -out ca.der"
openssl x509 -inform PEM -outform DER -in ca.pem -out ca.der

