#coding=utf8

import os
import sys
import re

#ANSI：　　　　　　　　gbk；
#Unicode： 　　　　　　前两个字节为FFFE；
#Unicode big endian：　前两字节为FEFF；　
#UTF-8：　 　　　　　　前两字节为EFBBBF

BYTE_ORDER_MARK = {'\xff\xfe' : 'UTF-16LE','\xfe\xff' : 'UTF-16BE'}

def Main():
    path = "."
    if len(sys.argv) >= 2:
        path = sys.argv

    if (not os.path.exists(path + "/tmp/")):
        os.mkdir(path + "/tmp/")
    
    for root, d, f in os.walk(path):
        for i in f:                
            filename = root + "/" + i
            tmpfilename = root + "/tmp/" + i
            
            if -1 != filename.find("tmp"):
                continue
            
            print("input file:" + filename)
            print("output file:" + tmpfilename)
            
            if filename.endswith(".txt"):
                print(filename)
                tmp = open(filename, "rb")

                byte_order_mark = tmp.read(5)

                tmp.seek(0,0)
                if byte_order_mark[:3] == '\xef\xbb\xbf':
                    tmp.close()
                    continue

                data = tmp.read()
                tmp.close()

                try:
                    if BYTE_ORDER_MARK.get(byte_order_mark[:2], None):
                        data = data.decode(BYTE_ORDER_MARK.get(byte_order_mark[:2], None)).encode("utf-8")
                    else:
                        data = data.decode("gbk").encode("utf8")

                    print('ok')
                except Exception:
                    #print(e)
                    print('failed')

                tmp = open(tmpfilename, "wb")
                tmp.write(data)
                tmp.close()

if __name__ == "__main__":
    Main()
