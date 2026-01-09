echo "Building Pastr"
xcodebuild -scheme Pastr -configuration Release -archivePath ~/Desktop/Pastr.xcarchive archive
echo "Build complete, moving Application"
cp -R ~/Desktop/Pastr.xcarchive/Products/Applications/Pastr.app /Applications/
echo "Done 👍"
