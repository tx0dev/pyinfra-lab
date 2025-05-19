Output docs/kind_flux.webm
Set Theme tokyonight
Set FontFamily "Hack"
Set FontSize 18
Set Width 1200
Set Height 600
Set Padding 20
Set Shell fish
Sleep 500ms
Type "./lab.fish rebuild"
Sleep 400ms
Enter
Wait
Sleep 2s
Type "./lab.fish full kind+flux"
Sleep 400ms
Enter 1
Wait@60s
Sleep 5s
Hide
Sleep 20s
Show
Type "./lab.fish ssh kind+flux kubectl get nodes"
Enter 1
Sleep 5s
