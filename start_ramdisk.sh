#!/bin/bash

# Mount tmpfs for Ramdisk
echo q | sudo -S mount -t tmpfs -o size=10G tmpfs /home/sughosha/Ramdisk

# Create necessary directories in the Ramdisk
echo q | sudo -S mkdir -p /home/sughosha/Ramdisk/Cursor_app  /home/sughosha/Ramdisk/Cursor_config  /home/sughosha/Ramdisk/Cursor_home  /home/sughosha/Ramdisk/VSCode_config /home/sughosha/Ramdisk/VSCode_home /home/sughosha/Ramdisk/Chrome_config /home/sughosha/Ramdisk/MSEdge_config /home/sughosha/Ramdisk/VSCodium_config  /home/sughosha/Ramdisk/VSCodium_home /home/sughosha/Ramdisk/Codegpt

# Create default config directories in the Ramdisk
echo q | sudo -S mkdir -p /home/sughosha/Ramdisk/Default/Cursor_config /home/sughosha/Ramdisk/Default/Cursor_home

# Copy necessary files to Ramdisk
echo q | sudo -S cp -ra /home/sughosha/Applications/cursor-0.44.11x86_64.AppImage /home/sughosha/Ramdisk/Cursor_app
echo q | sudo -S cp -ra /home/sughosha/.config/Cursor_disk/* /home/sughosha/Ramdisk/Cursor_config
echo q | sudo -S ln -s /home/sughosha/Ramdisk/Cursor_config /home/sughosha/.config/Cursor
echo q | sudo -S cp -ra /home/sughosha/.cursor_disk/* /home/sughosha/Ramdisk/Cursor_home
echo q | sudo -S ln -s /home/sughosha/Ramdisk/Cursor_home /home/sughosha/.cursor
#echo q | sudo -S cp -riva /home/sughosha/.config/Code_disk/* /home/sughosha/Ramdisk/VSCode_config
#echo q | sudo -S ln -s /home/sughosha/Ramdisk/VSCode_config /home/sughosha/.config/Code
#echo q | sudo -S cp -riva /home/sughosha/.vscode_disk/* /home/sughosha/Ramdisk/VSCode_home
#echo q | sudo -S ln -s /home/sughosha/Ramdisk/VSCode_home /home/sughosha/.vscode
echo q | sudo -S cp -ra /home/sughosha/.config/VSCodium_disk/* /home/sughosha/Ramdisk/VSCodium_config
echo q | sudo -S ln -s /home/sughosha/Ramdisk/VSCodium_config /home/sughosha/.config/VSCodium
echo q | sudo -S cp -ra /home/sughosha/.vscode-oss_disk/* /home/sughosha/Ramdisk/VSCodium_home
echo q | sudo -S ln -s /home/sughosha/Ramdisk/VSCodium_home /home/sughosha/.vscode-oss
echo q | sudo -S cp -ra /home/sughosha/.codegpt_disk/* /home/sughosha/Ramdisk/Codegpt
echo q | sudo -S ln -s /home/sughosha/Ramdisk/Codegpt /home/sughosha/.codegpt
echo q | sudo -S cp -ra /home/sughosha/.config/google-chrome_disk/* /home/sughosha/Ramdisk/Chrome_config
echo q | sudo -S ln -s /home/sughosha/Ramdisk/Chrome_config /home/sughosha/.config/google-chrome
echo q | sudo -S cp -ra /home/sughosha/.config/microsoft-edge_disk/* /home/sughosha/Ramdisk/MSEdge_config
echo q | sudo -S ln -s /home/sughosha/Ramdisk/MSEdge_config /home/sughosha/.config/microsoft-edge

# Copy default config directories in the Ramdisk
echo q | sudo -S cp -ra /home/sughosha/Ramdisk/Cursor_config/* /home/sughosha/Ramdisk/Default/Cursor_config
echo q | sudo -S cp -ra /home/sughosha/Ramdisk/Cursor_home/* /home/sughosha/Ramdisk/Default/Cursor_home

# Set appropriate permissions
echo q | sudo -S chmod -R 777 /home/sughosha/Ramdisk
