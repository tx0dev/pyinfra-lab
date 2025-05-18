Output rebuild_console.webm
Set Theme tokyonight
Set FontFamily "Hack"
Set FontSize 16
Set Width 1600
Set Height 800
Set Padding 20
Set Shell fish
Sleep 500ms
Type "time ./lab.fish rebuild +console"
Sleep 500ms
Enter
Wait@20s /debian-lab login/
Sleep 2s
Type "" # Ctrl+]
Wait
Sleep 3s
Type ./lab.fish ssh screenfetch
Sleep 400ms
Enter 1
Sleep 5s
