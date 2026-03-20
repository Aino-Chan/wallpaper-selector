Yet another wallpaper selector made with quickshell.
Inspired by https://github.com/liixini/skwd

Pretty beta at the moment expect bugs...

Screenshots:


Dependencies:
ffmpeg, linux-wallpaper-engine, quickshell, pywal, swww 
and dependencies of everything listed here as expected

Above dependecies are for plug and play behavior you can substitute pywal and sww dependecies
easily by changing wallpaper-apply.sh and wallpaper-apply-static.sh and using other tools
I cant add check for every tool and their locations if someone else does it they are welcome.

Installation:

Clone this repository and run setup.sh and follow along.
If you dont want to do that you can copy and edit scripts on scripts folder and copy them to ~/.local/bin and quickshell files to ~/.config/quickshell/ and edit freely if you lack dependencies that wont work so install script is recommended.

Scripts on scripts folder is as is copied pasted from what I use except 2 lines that hook up css generating scripts of mine dont expect for them to work out of box they are there for ease of copying and editing incase install script fails.
Automatic color change on the wallpaper selector 

Compositor compability:
Works in hyprland didnt test other compositors but it should work as long as it can detect your monitor and is wayland (I dont have intentions to add x11 support unless too many request the support shouldnt be too hard but I dont use x11 if someone adds a patch I will merge).


Disclaimer:
AI tools were used when making this fun project I am not hiding anything if you encounter serious bugs please inform me. ("Terrible" ui decisions were not effected by AI and readme was not written by AI as you can guess already [I hope])

for your color/css generating scripts if you dont directly create shemes with pywal I would suggest
hooking them on wallpaper-apply.sh and wallpaper-apply-static.sh and remove wal with the color generating tools you use

Usage:

Navigate using arrow keys mouse dragging or scroll wheel
Shift and clicking adds the hovered item to playlist and shift enter starts the playlist
Escape or clicking outside the application closes it (same goes for help pop up and suggestions dropdown menu)
Enter or double click applies the current selected wallpaper (double click works on everywhere)
Typing in ":" makes you enter command mode and you can type commands for functionality
You can edit the shell and add your own commands (altough it is quite messy atm)

Commands:
Please type :help for full command list and descriptions in text field.