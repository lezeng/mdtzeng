# coding=utf-8

import xml.etree.ElementTree as ElementTree
#from lxml import etree
#from xml.etree.ElementTree import *
import sys, os, re, zipfile
from hashlib import md5

# ==========================================================
# Hx@2014-12-03 :
# version 0.0.1
#
# Hx@2015-01-09 : 
# version 0.0.2
# 修正删除文件后md还在的Bug
# 将xml添加到zip中
# resourcemd5.xml文件解压路径错误
# config_dev.xml MD5 --> md5
#
# Hx@2015-02-15 : 
# 过滤掉linux隐藏文件 ^\.*\.*
#
# Hx@2015-03-23 : 
# 优化代码
# 调整了部署结构
# ==========================================================

def formatPathStr(path):
	return re.sub(r"[\\/]", '/', path)

# Hx@2014-12-02 : support functions
def getpwd():
	pwd = sys.path[0]
	if os.path.isfile(pwd):
		pwd = os.path.dirname(pwd)
	return pwd


CurPath = formatPathStr(getpwd())
DocumentRoot = CurPath + "/clientResouce"
ResourceRoot = DocumentRoot + "/Resource"

ResouceFile = "Resource.zip"
ResourceIndexFile = "ResourceMD5.xml"
ResourceIndexFileZip = "ResourceMD5.zip"
ResourceIndexFileMD5 = "ResourceMD5md5.txt"


def getAllFilesUnderPath(path):
	arr = []
	for root, dirs, files in os.walk(path):
		for fn in files:
			arr.append(re.sub(path + "/", "", formatPathStr(root + "/" + fn)))
	return arr

def generateFileMD5(path):
	md = md5()
	fp = open(path, "rb")
	if (not fp):
		return None
	md.update(fp.read())
	fp.close()
	return md.hexdigest()

def getFileType(filename):
	name, filetype = os.path.splitext(filename)
	return filetype

def getRelativePath(path, root):
	return re.sub(root, "", path)

def zipDir(dirname, zipfilename):
	filelist = []
	if os.path.isfile(dirname):
		filelist.append(dirname)
	else :
		for root, dirs, files in os.walk(dirname):
			for name in files:
				filelist.append(os.path.join(root, name))

	zf = zipfile.ZipFile(DocumentRoot + "/" + zipfilename, "w", zipfile.zlib.DEFLATED)
	for tar in filelist:
		arcname = tar[len(dirname):]
		zf.write(tar,arcname)
	zf.close()

def zipAdd(zipFile, addFile, addFileAlias):
	print(zipFile)
	zf = zipfile.ZipFile(zipFile, "a", zipfile.zlib.DEFLATED)
	zf.write(addFile, addFileAlias)
	zf.close()
	

class ResourceMgr:
	def __init__(self):
		self._filezip = DocumentRoot + "/" + ResourceIndexFileZip
		self._filemd5 = DocumentRoot + "/" + ResourceIndexFileMD5
		self._file = DocumentRoot + "/" + ResourceIndexFile
		self._tree = {}
		self._root = {}

	def getFileNameZip(self):
		return self._filezip
	def getFileName(self):
		return self._file

	def createIndexFile(self):
		objFile = open(self._file, "w")
		objFile.write('<dict><file md5="md5val">filepath</file></dict>')
		objFile.close()

	def read(self):
		if (os.path.isfile(self._filezip)):
			fZip = zipfile.ZipFile(self._filezip, 'r')
			fZip.extract(ResourceIndexFile, DocumentRoot)
		else:
			self.createIndexFile()
		self._tree = ElementTree.parse(self._file)
		self._root = self._tree.getroot()
		return True
	
	def update(self, dicList):
		self.delNotExistFileMd5(dicList.keys())
		for sFile in dicList:
			self.updateSrc(sFile, dicList.get(sFile))
		
	def delNotExistFileMd5(self, arrFile):
		for node in self._root.findall("file"):
			bFind = False
			for sFile in arrFile:
				if (sFile == node.text):
					bFind = True

			if (bFind == False):
				print("remove: %s" % node.text)
				self._root.remove(node)

	def updateSrc(self, src, md):
		l = len(self._root.findall("file"))
		i = 0
		for node in self._root.findall("file"):
			if (node.text == src):
				node.set("md5", md)
				print("update: %s" % src)
				break
			i += 1

		if (i == l):
			print("add: %s" % src)
			ElementTree.SubElement(self._root,"file",
					{"md5":md}).text = src
			#ElementTree.dump(self._tree)
		
	def write(self):
		self._tree.write(self._file)
		self.generateZipFile()
		self.genarateIndexFileMD5()
		return True

	def delTmpFile(self):
		os.remove(self._file)
	
	def generateZipFile(self):
		fZip = zipfile.ZipFile(self._filezip, 'w')
		fZip.write(self._file, ResourceIndexFile)

	def genarateIndexFileMD5(self):
		objFile = open(self._filemd5, "w")
		objFile.write(generateFileMD5(self._filezip))



objResourceMgr = ResourceMgr()

if __name__ == '__main__':
	
	print("--PATH--")
	print(ResourceRoot)
	
	if (not objResourceMgr.read()):
		print("read resource failed")
	
	print("---update list---")
	arrFile = getAllFilesUnderPath(ResourceRoot)

	
	dicList = {}
	for sFile in arrFile:
		if re.match("^\.", os.path.basename(sFile)):
			print("delete: " + sFile)
			os.remove(ResourceRoot +"/"+ sFile)
			continue
		sPath = ResourceRoot + "/" + sFile
		dicList[sFile] = generateFileMD5(sPath)
	

	objResourceMgr.update(dicList)
	objResourceMgr.write()

	print("--- zip resource directory ---")
	zipDir(ResourceRoot, ResouceFile)
	zipAdd(DocumentRoot + "/" + ResouceFile, objResourceMgr.getFileName(), ResourceIndexFile)

	objResourceMgr.delTmpFile()
