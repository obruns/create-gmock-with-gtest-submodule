gmock with gtest submodule demonstration
========================================

Show how the `svn:externals` property can be converted into Git
submodule references when migrating Subversion repositories to Git.

This uses gmock and gtest because their histories are quite short so
that the overall process does not take too long.

You should run `git grep TODO -- gmock-with-gtest-submodule.sh` to
understand the weak spots of this script. You *must* customize the
script, it is unlikely to run as-is.

There is a short example how to verify the result by building gmock and
running its test suite. Regardless of a (possible) negative outcome, the
repository is pushed to the remote.
