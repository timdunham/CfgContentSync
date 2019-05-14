# Infor CPQ Configurator Content Sync script

**WARNING. This utility is provided as is.  There is guarantee or assurances regarding it's use*

This utility will assist in synchronizing Configurator Content between a local folder and the Cloud services

## Settings
Download the utilty and execute it from a powershell terminal.

> `.\sync-content.ps`

> If this fails, run
>
>`Add-Type -AssemblyName "System.Web"` 
>
>from the powershell >prompt first.

When this powershell script is executed it will prompt for 3 things.

1. Tenant Id.  (e.g. CUSTOMER_DEV)
2. Domain (e.g. configurator.inforcloudsuite)
    * configurator.inforcloudsuite.com (us-east)
    * configurator.eu1.inforcloudsuite.com (eu-central)
    * configurator.se2.inforcloudsuite.com (apac)
3. Cookies
    * Cookies need to be captured from your browser.  More information on how to do that below.

## Synching content
After prompting for these settings, you can sync local content to the cloud by using:

`sync-LocalToCloud`

or cloud content to the local folder using:

`sync-CloudToLocal`

By default, the utility will display the files that would be copied, but will not actually move files.  Files and folders that will be added show up as Green text with a '+'.  Files that will be removed show up as Red text with a '-'.  Files that exist in both locations will show as normal text.

To force the utility to perform the copy/delete operations, add the `-commit $true` parameter.

> `sync-LocalToCloud -commit $true`

The local folder that is used is the current directory by default.  If you wish to target a different folder you can set that with the `-localFolder` parameter.

> `sync-LocalToCloud -localFolder "c:\mycontent"`

## Getting Cookie Data
For the utility to work, you must first log in to the online Content Manager and capture the cookies.

1. Using Chrome, Log in to your tenant
2. Navigate to CPQ Workbench
3. Navigate to Configurator Settings > Cloud > Content Manager
4. Right-click on Content Root and click "open link in new tab"
5. Click f12 to open Developer Tools
6. Select the Network tab in Developer Tools
7. Click on a folder.  You will see a network request that starts with "GetFile"
8. Click on that request and find the Cookies Header on the Header tab.  Select the entire cookie text.  *This is the text that you should paste when prompted during setup*

![Alt](/cookies.png "Cookies")

## Notice
When using this utility with `-commit $true` be sure not to navigate around or use the Content Manager in Workbench while the utility is running.
