$global:currentParamName = ""

function GetPropertyValue{
    param(
        [string]$yamlLine
        )

    $paramValue = $yamlLine.Split(":")[1]
    $paramValue = $paramValue -replace "'",""

    return $paramValue.trim()
}

function ReplacePlaceholder{
    param(
        [string]$placeholderType,
        [string]$str,
        [hashtable]$placeholderHash
    )

    $prefix = "\$\{\{$placeholderType."
    $suffix =  "}}"
    if ($str -like "*$placeholderType.*"){
        $propertyName = (($str -split $prefix)[1] -split $suffix)[0]
        $propertyValue =$placeholderHash[$propertyName]
        $str = $str -replace ($prefix + $propertyName + $suffix), $propertyValue
    }

    return $str
}

function CreateIndentation{
    param(
        $indentationCount
    )
    $str = "";
    while ($indentationCount -gt 0) {
        $str += " "
        $indentationCount = $indentationCount - 1
    }
    return $str
}

function SetParametersHash{
    param(
        [hashtable]$parametersHash,
        [string]$parametersYaml
    )

    $name = "- name:"
    $default = "default:"
    
    if ($parametersYaml -like "*$name*"){
        $global:currentParamName = GetPropertyValue -yamlLine $parametersYaml
        if ($parametersHash.ContainsKey($global:currentParamName) -eq $false){
            $parametersHash.Add($global:currentParamName,"");
        }
    } elseif ($parametersYaml -like "*$default*") {
        $paramValue = GetPropertyValue -yamlLine $parametersYaml
        if ($parametersHash[$global:currentParamName] -eq ''){
            $parametersHash[$global:currentParamName] = $paramValue
        }
    } elseif ($parametersYaml -like "*- *") {
        $paramValue = GetPropertyValue -yamlLine $parametersYaml
        $paramName = ((($parametersYaml -split "-")[1] -split ":")[0]).trim()

        if ($parametersHash.ContainsKey($paramName) -eq $false){
            $parametersHash.Add($paramName,$paramValue);
        } elseif ($parametersHash[$paramName] -eq ''){
            $parametersHash[$paramName] = $paramValue;
        }
    }

    return $parametersHash
}

function ParseTemplate{
    param (
        [string]$templatePath,
        [hashtable]$yamlParams
    )

    ## Get Yaml
    $templateYaml = Get-Content -Path $templatePath 

    $processedParameters = $false
    $processingParameters = $false
    $startPrefixRemoved = $false


    $rebuiltTemplateYaml = ""

    foreach ($yamlLine in $templateYaml){
        
        ## If break in YAML then assume template block finished
        if (($yamlLine -replace "\s","" -replace "`t","") -eq "") {
            $processingParameters = $false
        }

        ## Start processing Template Parameters
        if ($yamlLine -like "parameters:*" -and $processedParameters -eq $false){
            $processingParameters = $true
        } 
        ## Get Parameters Name/Values
        elseif ($processingParameters -eq $true -and $yamlLine -notLike "*#*") {
           $yamlParams = SetParametersHash -parametersHash $yamlParams -parametersYaml $yamlLine
        }
        ## Remove Template Array Prefix
        elseif ($startPrefixRemoved -eq $false -and ($yamlLine -like "*stages:*" -or $yamlLine -like "*jobs:*")) {
            $startPrefixRemoved = $true
        }
        ## Update the Yaml Template
        else {
            $yamlLine = ReplacePlaceholder -placeholderType "parameters" -str $yamlLine -placeholderHash $yamlParams

            $rebuiltTemplateYaml += (&{If($yamlLine.count -gt 1) {$yamlLine.Substring(1)} Else {$yamlLine}}) + "`n"
        }
    }

    return $rebuiltTemplateYaml
}

function processMainPipeline{
    param(
        $pipelineYamlName,
        $rootPath
        )

    $pipelineYaml = Get-Content -Path ($rootPath + $pipelineYamlName) 

    $processingTemplate = $false
    $rebuiltPipelineYaml = ""
    $templateParameters = @{}
    $templatePath = ""
    foreach ($yamlLine in $pipelineYaml){

        if ($processingTemplate -eq $true -and ($yamlLine -replace "\s","" -replace "`t","") -eq "") {   

            $templateYaml = ParseTemplate -templatePath ($rootPath + $templatePath) -yamlParams $templateParameters

            $rebuiltPipelineYaml += "`n" + $templateYaml + "`n"

            $processingTemplate = $false
            $templateParameters = @{}
        }

        ## Start processing Template
        if ($yamlLine -like "*- template*" -and $yamlLine -notLike "*#*" -and $yamlLine -notLike "*yml@*"){

            $templatePath = (GetPropertyValue -yamlLine $yamlLine).trim()
            $processingTemplate = $true

        } 
        ## Process template parameters
        elseif ($processingTemplate -eq $true -and $yamlLine -notLike "*#*" -and $yamlLine -notLike "*parameters:*") {
            $paramValue = (GetPropertyValue -yamlLine $yamlLine).trim()
            $paramName = (($yamlLine -split ":")[0]).trim()

            if ($templateParameters.ContainsKey($paramName) -eq $false){
                $templateParameters.Add($paramName,$paramValue);
            } elseif ($templateParameters[$paramName] -eq ''){
                $templateParameters[$paramName] = $paramValue;
            }
        } 
        ## Update rebuilt YAML
        else {
            $rebuiltPipelineYaml += $yamlLine + "`n"
        }
    
    }
    
    ## Create new full YAML
    $outputPath = "$rootPath\full-$pipelineYamlName"
    Write-Host "Output to $outputPath"
    Set-Content -Path $outputPath -Value $rebuiltPipelineYaml

    return $outputPath
}
