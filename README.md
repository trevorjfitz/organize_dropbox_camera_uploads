# organize_dropbox_camera_uploads
A powershell script to organize the Camera Uploads folder in Dropbox.

Yes, Dropbox has a similar automatic function, but when I started using Camera Uploads in 2015(?) it did not exist. The folder grew so large (65k+ images and videos), that I could no longer open the folder in the browser, or on Windows, without crashing.

# script modification ideas
The script scans for all files in Camera Uploads, than organizes them into a YYYY/Month folder structure. To change the folder naming convention, edit this code:

```
$monthName = (Get-Culture).DateTimeFormat.GetMonthName([int]$month)
$folderPath = "$FOLDER_TO_ORGANIZE/$year/$monthName"
```

If your image files follow a date pattern, make sure to add relevant regex statements to this list so it can parse the date data:

```
$patterns = @(
    @{Regex = "(\d{4})-(\d{2})-(\d{2})";}, # Standard YYYY-MM-DD
    @{Regex = "IMG_(\d{4})(\d{2})(\d{2})";}, # IMG_YYYYMMDD
    @{Regex = "(\d{4})(\d{2})(\d{2})_";} # YYYYMMDD_HHMMSS.jpg
)
```

# prereq: setup of dropbox app
Before you can run the script, you will have to create your own Dropbox App and grant it the following permissions:
 - account_info.read (default permission)
 - files.metadata.read (default permission)
 - files.content.write (so you can move the files into the corresponding folders)

After the Dropbox App is setup, generate an Access Token. Pass that token into the script.

# execute script
In a powershell console, execute the command `bulk-organize.ps1 -MaxFilesToProcess # -AccessToken [insert token]`

Suggestion, start with a small number of files to ensure the script is behaving as you expect.

# want it to go faster?
The bottleneck is the actual moving of files by Dropbox. A smart person could probably make this whole thing faster by initating all of the move jobs asynchronously. But I opted to babysit the process a little bit over a day or two.
