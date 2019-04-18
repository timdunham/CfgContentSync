#Add-Type -AssemblyName "System.Web"
$defaultTenant = "CPQCLM3_AX1"
$defaultDomain = "cfgax1.cpq.awsdev.infor.com"

add-type @"
using System.Net;
using System.Web;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
 

function get-FilesForFolder([Folder] $folder)
{
    Process {
        $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/GetFile?folderId=$($folder.Id)&instanceName=$($global:settings.tenant)&applicationName=$($global:settings.tenant)" 
        $response = (Invoke-WebRequest -Headers $null -WebSession $global:settings.session -Uri $uri)
        $files = $response.Content | ConvertFrom-Json
        #write-host "    Server Folder is $($folder.path)"
        $files | ForEach-Object { [File]::new($_.name, $_.id, $folder) }
    }
}
function get-LocalTree([string] $localFolder)
{
    Process {
        [folder]::new( $(get-item $localFolder), "", "." )    
    }
}



##############################################################
##
## CLASSES
##
##############################################################
Class Folder
{
    Folder([System.IO.FileSystemInfo] $folder, [string] $path, [string]$name) {
        $this.directory = $folder;
        $this.name = $name;
        if ($path -ne "") { $this.path = "$path\$($this.name)"; } else { $this.path=$this.name }
        $this.isLocal = $true;
    }
    Folder([string]$name, [int32]$id, [string]$path, [object[]]$children){
        if ($children -eq $null) { $children = @()}
        $this.name = $name;
        $this.id = $id;
        if ($path -ne "") { $this.path = "$path\$($this.name)"; } else { $this.path=$this.name }
        $this.folders = @($children | ForEach-Object { [Folder]::new( $_.data.title, $_.attr.id, $this.path, $_.children ) } )
        $this.isLocal=$false;        
    }

    [string] $name;
    [string] $path;
    [int32] $id;
    [System.IO.FileSystemInfo] $directory;
    [boolean] $isLocal;
    [Folder[]] $folders;
    [File[]] $files;
    [Folder[]] GetFolders(){
        if ($this.folders -eq $null) {
            if ($this.isLocal){
                $this.folders = @($this.directory.GetDirectories() | foreach-object { [Folder]::new($_, $this.path, $_.Name) })
            }
        }
        return $this.folders;
    }
    [File[]] GetFiles() {
        if ($this.files -eq $null){
            if ($this.isLocal) {
                $this.files = @($this.directory.GetFiles() | ForEach-Object { [File]::new($_.name, $this) })
            } else {
                $this.files = get-FilesForFolder $this;
            }
        }
        return $this.files;
    }
    [void]Delete() {
        if ($this.isLocal) {
            remove-item -LiteralPath $this.path -Recurse -Force 
        } else {
            $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/FolderDelete?id=$($this.id)&instanceName=$($global:settings.tenant)&applicationName=$($global:settings.tenant)"
            $response = (Invoke-WebRequest -Headers $null -WebSession $global:settings.session -Uri $uri).Content | ConvertFrom-Json
            # check for error?
        }
    }

    [void] AddFile([File]$file) {
        if ($this.isLocal) {
            $filePath = "$($this.path)\$($file.name)"
            $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/DownloadFile?fileId=$($file.Id)&instanceName=$($global:settings.tenant)&applicationName=$($global:settings.tenant)"
            $response = Invoke-WebRequest -Headers $null -WebSession $global:settings.session -Uri $uri -OutFile $filePath
        } else {
            $filePath = $(get-item $file.path).FullName
            #this expects the target folder to be the last one that received the "GetFiles" call--this is poor from an API standpoint
            $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/FileUpload"
            $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
            $fileEnc = [System.Text.Encoding]::GetEncoding('iso-8859-1').GetString($fileBytes);
            $boundary = [System.Guid]::NewGuid().ToString(); 
            $LF = "`r`n";

            $bodyLines = ( 
                "--$boundary",
                "Content-Disposition: form-data; name=`"file`"; filename=`"$($file.name)`"",
                "Content-Type: $([System.Web.MimeMapping]::GetMimeMapping($FilePath))$LF",
                $fileEnc,
                "--$boundary--$LF" 
            ) -join $LF

            $response = Invoke-RestMethod -Uri $uri -Headers $Null -Method Post -WebSession $global:settings.session -ContentType "multipart/form-data; boundary=`"$boundary`"" -Body $bodyLines
        }

    }
    [Folder] AddFolder([Folder] $folder) {
        if ($this.isLocal){
            $newDirectory = new-item -ItemType Directory "$($this.path)\$($folder.name)"; 
            $newFolder = [Folder]::new($newDirectory, $this.path, $newDirectory.name);
        } else {
            $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/FolderCreate?parentId=$($this.Id)&folderName=$($folder.name)&instanceName=$($global:settings.tenant)&applicationName=$($global:settings.tenant)"
            $response = (Invoke-WebRequest -Headers $null -WebSession $global:settings.session -Uri $uri).Content | ConvertFrom-Json
            $newFolder = [Folder]::new($folder.name, $response.Id, $this.path, @());
            $this.files = get-FilesForFolder $newFolder;
        }
        $this.folders += $newFolder;
        return $newFolder;
    }
}

Class File {
    File([string] $name, [Folder]$parent) {
        $this.name=$name;
        $this.parent=$parent;
        $this.path = "$($parent.path)\$($this.name)"
    }
    File([string] $name, [int32] $id, [Folder]$parent) {
        $this.name=$name;
        $this.id=$id;
        $this.parent=$parent;
        $this.path = "$($parent.path)\$($this.name)"
    }
    [string]$name;
    [string]$path;
    [int32]$id;
    [Folder] $parent;

    [void]Delete() {
        if ($this.parent.isLocal) {
            $filePath = "$($this.parent.path)\$($this.name)"
            remove-item -Path $filePath -Force
        } else {
            $uri = "https://$($global:settings.domain)/ContentUploaderInternal/UserFile/FileDeleteV2?id=$($this.id)&instanceName=$($global:settings.tenant)&applicationName=$($global:settings.tenant)"
            $response = Invoke-WebRequest -Headers $null -WebSession $global:settings.session -Uri $uri
        }
    }
}

Class Settings {
    [string] $tenant;
    [Microsoft.PowerShell.Commands.WebRequestSession] $session; 
    [string] $domain = "cfgax1.cpq.awsdev.infor.com";

    Settings([string] $tenant, [string]$domain, [string]$cookies){
        $this.session= New-Object Microsoft.PowerShell.Commands.WebRequestSession; 
        $this.tenant = $tenant;
        $this.domain = $domain;

        $cookieArray=$cookies.Split(";");
        $cookieArray | ForEach-Object { $this.AddCookieToSession($_.Trim()) }
    }
    [void] AddCookieToSession([string]$cookieString){
        $name,$value=$cookieString.split("=");
        if ($name -ne "PCM_Configurator_FalconSts1"){
            $cookie = New-Object System.Net.Cookie
            $cookie.Name = $name
            $cookie.Value = $value
            $cookie.Domain = "infor.com"
            $this.session.Cookies.Add($cookie)
            $cookie = New-Object System.Net.Cookie
            $cookie.Name = $name
            $cookie.Value = $value
            $cookie.Domain = "inforcloudsuite.com"
            $this.session.Cookies.Add($cookie)
        }
    }
}
##############################################################
##
## SET FUNCTIONS
##
##############################################################
function except-Lists {
    Param([parameter(ValueFromPipeline)] [object[]] $source,
          [parameter(ValueFromPipelineByPropertyName)] [object[]] $without)
    Process {
        $names = @($without | select -expand name -Unique)
        $source | Where-Object { -Not ($names -Contains $_.name)  }
    }
}
function innerjoin-Lists {
    Param([parameter(ValueFromPipeline)] [object] $source,
          [parameter(ValueFromPipelineByPropertyName)] [object[]] $with)
    Process {
        $target = $with | ? { $_.name -eq $source.name }
        if ($target -ne $null) {
            [pscustomobject]@{source=$source; target=$target;}
        }
    }
}


function get-CloudFolderTree
{
    $uri = "https://$($settings.domain)/ContentUploaderInternal/UserFile/GetFolderListV2?instanceName=$($settings.tenant)&applicationName=$($settings.tenant)"
    $response = (Invoke-WebRequest -WebSession $settings.session -Uri $uri)
    $folders = $response.Content | ConvertFrom-Json
    $folders[0].data.title = "."
    return [folder]::new(".", $folders.attr.id, "", $folders.children);
}

function sync-Folder {
    Param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $source,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $target,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        write-host "  $($source.path)\"
        $deletedFiles =  $target.GetFiles() | except-Lists -without $source.GetFiles() 
        $deletedFiles | delete-File -commit $commit 

        $sharedFiles = $source.GetFiles() | innerjoin-Lists -with $target.GetFiles() 
        $sharedFiles | ForEach-Object { update-file -file $_.target -sourceFile $_.source -targetFolder $target -commit $commit }

        $addedFiles = $source.GetFiles() | except-Lists -without $target.GetFiles() 
        $addedFiles | copy-File -targetFolder $target -commit $commit



        $deletedFolders =$target.GetFolders() | except-Lists -without $source.GetFolders() 
        $deletedFolders | delete-Folder -commit $commit

        $sharedFolders = $source.GetFolders() | innerjoin-Lists -with $target.GetFolders() 
        $sharedFolders | ForEach-Object { sync-Folder -source $_.source -target $_.target -commit $commit }

        $addedFolders =  $source.GetFolders() | except-Lists -without $target.GetFolders() | create-Folder -targetFolder $target -commit $commit 
        #$addedFolders | sync-Folder -target $target -commit $commit

    }
}


##############################################################
##
## Commit File/Folder Changes
##
##############################################################
function delete-File {
    Param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [File] $file,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $folder,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        if ($file -ne $null) {
            write-host "- $($file.path)" -BackgroundColor Red
            if ($commit) { $file.Delete() }
            #$file
        }
    }
}
function delete-Folder {
    Param([parameter(ValueFromPipeline)] [Folder] $folder,
          [parameter(ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        write-host "- $($folder.path)\" -BackgroundColor Red
        $folder.GetFiles() | delete-File -folder $folder -commit $false #commit=false because remove directory will be recursive
        $folder.GetFolders() | delete-Folder -commit $false             #commit=false because remove directory will be recursive
        if ($commit) { $folder.Delete() }
        #$folder
    }
}
function copy-File {
    Param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [File] $file,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $targetFolder,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        if ($file -ne $null) {
            write-host "+ $($file.path)" -BackgroundColor Green
            if ($commit) { $newFile = $targetFolder.AddFile($file) }
            $newFile
        }
    }
}
function create-Folder {
    Param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $folder,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $targetFolder,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        if ($folder -ne $null) {
            write-host "+ $($folder.path)" -BackgroundColor Green
            if ($commit) { $newFolder = $targetFolder.AddFolder($folder) } 
            $folder.GetFiles() | copy-File -targetFolder $newFolder -commit $commit
            $folder.GetFolders() | create-Folder -targetFolder $newFolder -commit $commit
            $newFolder
        }
    }
}
function update-File {
    Param([parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [File] $file,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [File] $sourceFile,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [Folder] $targetFolder,
          [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)] [boolean] $commit= $false)
    Process {
        write-host "  $($targetFolder.path)\$($sourceFile.name)" 
        #if ($commit) { $newFolder = $targetFolder.AddFolder($folder.name) }
        #$newFolder
    }
}

function sync-CloudToLocal
{
    Param([parameter(ValueFromPipelineByPropertyName)] [string] $localFolder="",
          [parameter(ValueFromPipelineByPropertyName)] [pscustomobject] $commit=$false)

    $source = get-CloudFolderTree 
    if ($localFolder -eq "") { $localFolder = ".\" }
    $target = get-LocalTree $(get-item $localFolder)
    sync-Folder $source $target -commit $commit

}

function sync-LocalToCloud
{
    Param([parameter(ValueFromPipelineByPropertyName)] [string] $localFolder="",
          [parameter(ValueFromPipelineByPropertyName)] [pscustomobject] $commit=$false)



    $target = get-CloudFolderTree 
    if ($localFolder -eq "") { $localFolder = ".\" }
    $source = get-LocalTree $(get-item $localFolder)
    sync-Folder $source $target -commit $commit

}
 
function prompt-ForSettings
{

    $tenant = Read-Host -Prompt "What is your tenant? [$defaultTenant]"
    if ([string]::IsNullOrWhiteSpace($tenant)) {
        $tenant = $defaultTenant;       
    }
    $domain = Read-Host -Prompt "What is your domain? [$defaultDomain]"
    if ([string]::IsNullOrWhiteSpace($domain)) {
        $domain = $defaultDomain;
    }
    $cookies = Read-Host -Prompt "Paste cookies."
    
    $global:settings = [Settings]::new($tenant, $domain, $cookies);
}

prompt-ForSettings