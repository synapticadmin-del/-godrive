@echo off
set PATH=C:\Users\kayf\AppData\Local\Android\Sdk\platform-tools;%PATH%
adb install -r "%USERPROFILE%\Desktop\SynapticGo-APKs\synaptic-go-rider-debug.apk"
adb install -r "%USERPROFILE%\Desktop\SynapticGo-APKs\synaptic-go-captain-debug.apk"
pause
