# What is this?
This is an iOS app you can run locally if you have a Mac/Xcode and a iPhone! 
# What's the app do? Who is Mira?
It's a Markov chain that uses merging of adjective-noun and noun-verb pairs, borrowing from Noam Chompsky's idea of SMT!
# Wait, why is this kinda good?
I don't know man I just work here!
Steps to run:
1. Open Xcode > Create new project
2. Choose iOs as platform, and Game as Application > Next
3. Xcode will make you choose a product name and a "team" and an origanization identifier, you can put anything since this is just for local running. > Next
4. A window to create a directory for the project should appear, I'd recommend saving it somewhere you typically save xcode projects,it will make a new folder with the product name in the dir you select.
5. Once xcode is open, replace GameViewController.swift in your project navigator with the source code provided in the repo.
6. This app uses your voice to talk to the markov chain. apple will make you give a reason for why this is being done. If you skip this step, you will get this error:

```txt
 This app has crashed because it attempted to access privacy-sensitive data without a usage description.
    The app's Info.plist must contain an NSSpeechRecognitionUsageDescription key with a string value explaining to the user how the app uses this data.:
```
7. Tap your product name in the project navigator. in xcode this will look like the app store icon above the main project folder where GameViewController.swift and the other files are located.
8. After you tap the project name, tap Info. In Custom iOS Target Properties, make a new property by pressing + next to an existing one. The properties you need to write reasons for are "Privacy - Microphone Usage Description" and 
9. you can put the values as "we use microphone to let you use your voice to talk to the markov chain" and "we use speech recogniton to let you use your voice to talk to the markov chain" but it shouldnt matter for local use.
10. optional: add the logo by clicking on the Assets in the project navigator then on AppIcon.
11. Connect your iPhone and build the project. 

