#
# Will create empty text files in all first-levet child directories of the current directory
# which will be named "Current Directory - Child Directory.txt"
# 
# Created for putting ID files in soundfont folders under a master author directory 
#

Get-ChildItem -Directory | ForEach-Object { $tf = $_.FullName + "\" + $_.Parent.Name + " - " + $_.Name + ".txt"; New-Item -ItemType File -Path $tf }
