function Write-Color([String[]]$Text, [ConsoleColor[]]$Color) {
    for ($i = 0; $i -lt $Text.Length; $i++) {
        Write-Host $Text[$i] -Foreground $Color[$i] -NoNewLine
    }
    Write-Host
}

$BaseColor='Blue'
$LightningFragmentsColor='Yellow'
$SnakeFragmentsColor='Green'
$TextFragments = @()
$Colors = @()
$TextFragments+="                          _                              _          _$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="                         | |                            | |        | |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="                         | |                            | |      _ | |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="    __________"
$Colors+=$BaseColor
$TextFragments+="  _______"
$Colors+=$LightningFragmentsColor
$TextFragments+=" _| |__ _ __ __________  _  ____ | |  __ |_|| |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="   /  ____    \"
$Colors+=$BaseColor
$TextFragments+="\____   /"
$Colors+=$LightningFragmentsColor
$TextFragments+="_   __| Y _|  ____    \| Y     \|  Y   \   | |"
$Colors+=$BaseColor
$TextFragments+=" ____$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="  |  |    |   |"
$Colors+=$BaseColor
$TextFragments+="    /  /"
$Colors+=$LightningFragmentsColor
$TextFragments+="  | |  | / |  |    |   ||   ___  |   __  |_ | |"
$Colors+=$BaseColor
$TextFragments+="/ x  \$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="  |  |    |   |"
$Colors+=$BaseColor
$TextFragments+="   /  /"
$Colors+=$LightningFragmentsColor
$TextFragments+="   | |  | | |  |    |   ||  |   | |  |  | | || |"
$Colors+=$BaseColor
$TextFragments+="  ___/$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="  |  |____|   |"
$Colors+=$BaseColor
$TextFragments+="  /  /"
$Colors+=$LightningFragmentsColor
$TextFragments+="    | |  | | |  |____|   ||  |___| |  |  | | || |"
$Colors+=$BaseColor
$TextFragments+=" /$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="  |           \"
$Colors+=$BaseColor
$TextFragments+=" /  /____"
$Colors+=$LightningFragmentsColor
$TextFragments+=" | |__| | |           \|        |  |  | | || |__"
$Colors+=$BaseColor
$TextFragments+=" __/\$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="  \_________/\_"
$Colors+=$BaseColor
$TextFragments+="|_______/"
$Colors+=$LightningFragmentsColor
$TextFragments+=" \___/|_| \_________/\_|   ____/|__|  |_|_|\___/"
$Colors+=$BaseColor
$TextFragments+="____/$([Environment]::NewLine)"
$Colors+=$SnakeFragmentsColor
$TextFragments+="                                               |  |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="                                               |  |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="                                               |  |$([Environment]::NewLine)"
$Colors+=$BaseColor
$TextFragments+="                                               |__|"
$Colors+=$BaseColor
$TextFragments+="  TODO_INSERT_SLOGAN$([Environment]::NewLine)"
$Colors+='White'

Write-Host
Write-Color -Text $TextFragments -Color $Colors
