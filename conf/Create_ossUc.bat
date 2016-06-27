@echo off
set path=%~dp0

set game_version=1.04

::web root
set webpath=%path%
set webroot=%webpath%clientResouce\

::conf path
set conf_path_game_setting=%path%gameSetting\
set conf_path_fight_setting=%path%fightSetting\
set conf_path_clientonly_setting=%path%ClientOnlySetting\
set conf_path_activity_setting=%path%activitySetting\

set conf_path_oss=%path%ossuc\
set conf_path_http=%conf_path_oss%%game_version%\


::desc
set path_web_setting=%webroot%Resource\setting\
set path_web_script=%webroot%Resource\script\

set lastPath=%cd%

echo ">>>copy clinet setting"
mkdir %path_web_setting%tmp\
copy %conf_path_clientonly_setting%*.xml %path_web_setting%
copy %conf_path_clientonly_setting%ConvertertoUTF8_ver2.py %path_web_setting%tmp\
copy %conf_path_clientonly_setting%*.txt %path_web_setting%tmp\
copy %conf_path_game_setting%client\*.txt %path_web_setting%tmp\
copy %conf_path_fight_setting%client\*.txt %path_web_setting%tmp\
copy %conf_path_activity_setting%client\*.txt %path_web_setting%tmp\


echo ">>>conv clinetonly setting"
cd %path_web_setting%tmp\
start /wait python ConvertertoUTF8_ver2.py
cd %path%

copy %path_web_setting%tmp\tmp\ %path_web_setting%

echo ">>>encrypt clinetonly setting"
set en_path_web_setting=%path_web_setting%
set utf8_path_web_setting=%path_web_setting%tmp\tmp\

cd %utf8_path_web_setting%
for  %%s in (*.txt) do ( 
echo %%s
%path%encrypt.exe %utf8_path_web_setting%%%s %en_path_web_setting%%%s
) 

echo ">>>encrypt server_list"
%path%encrypt.exe  %conf_path_http%server_list.txt %conf_path_http%dst\server_list.txt

cd %path%

del /f/s/q %path_web_setting%tmp\tmp\
rd /s/q %path_web_setting%tmp\tmp\
del /f/s/q %path_web_setting%tmp\
rd /s/q %path_web_setting%tmp\

echo ">>>luajit script"
del /f/s/q %path_web_script%*.lua
del /f/s/q %path_web_script%formation\*.lua
del /f/s/q %path_web_script%resBattle\*.lua

cd %conf_path_http%script\
for  %%s in (*.lua) do ( 
echo %%s
%path%encrypt.exe %conf_path_http%script\%%s %path_web_script%%%s
) 

cd %conf_path_http%script\formation\
for  %%s in (*.lua) do ( 
echo %%s
%path%encrypt.exe %conf_path_http%script\formation\%%s %path_web_script%formation\%%s
) 

cd %conf_path_http%script\resBattle\
for  %%s in (*.lua) do ( 
echo %%s
%path%encrypt.exe %conf_path_http%script\resBattle\%%s %path_web_script%resBattle\%%s
) 
copy 


copy 
echo ">>>make md5"
cd %webpath%
start /wait python createResourceIndex.py

copy %webroot%ResourceMD5* %conf_path_http%dst\
cd %path%
