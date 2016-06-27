import os
ROOTDEST = "./clientResouce/Resource"
MD5DEST = "./clientResouce"
CODEDEST = "../client/SHW_Client/SHW_Client/Resources"

output = os.system("rm -rf " + CODEDEST +"/ResourceMD5.*")
output = os.system("rm -rf " + CODEDEST +"/setting")
output = os.system("cp -rf " + ROOTDEST + "/* " + CODEDEST)
output = os.system("cp -rf " + MD5DEST + "/ResourceMD5* " + CODEDEST)
