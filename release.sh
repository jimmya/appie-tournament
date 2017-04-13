branch=`git rev-parse --abbrev-ref HEAD`
if [ "$branch" != "develop" ]; then
  echo -e "\x1B[33m⚠️ Current branch is not develop. Make sure you are on develop to release this app. ⚠️\x1B[0m"
  exit 1
fi

if [[ `git status --porcelain` ]]; then
    echo -e "\x1B[33mLocal changes detected:\x1B[0m"
    git status --porcelain
    echo -e "\x1B[33mPlease enter a commit message: \x1B[0m"
    read input_variable
    echo -e "\x1B[33mComitting changes\x1B[0m"
    git add .
    git commit -a -m "$input_variable"
    echo -e "\x1B[33mPushing changes\x1B[0m"
    git push origin develop
fi

git checkout master

if [[ `git diff origin/master origin/develop` ]]; then
  git merge develop
  echo -e "\x1B[33mMerging development with master\x1B[0m"
  git push origin master
fi

if [[ `git diff origin/master heroku/master` ]]; then
#  echo -e "\x1B[33mRunning test suite\x1B[0m"
#  vapor test
#  if [[ $? != 0 ]]; then
#    echo -e "\x1B[33m❗ Tests failed, aborting release! ❗\x1B[0m"
#    exit 1
#  fi
  echo -e "\x1B[33mPushing to Heroku\x1B[0m"
  git push heroku master
  if [[ $? == 0 ]]; then
      tag="`heroku config:get HEROKU_RELEASE_VERSION`-tst"
      git tag $tag
      git push origin $tag
      echo -e "\x1B[33m🚀 Push to Heroku succeeded, version is: $tag 🚀\x1B[0m"
  else
      echo -e "\x1B[33m❗ Push to Heroku failed ❗\x1B[0m"
      exit 1
  fi
else
  echo -e "\x1B[33m✅ Heroku is up to date with master, no push needed ✅\x1B[0m"
fi

git checkout develop
