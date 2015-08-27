#!/bin/sh

# create a local Subversion server and operate entirely inside tmpfs
# to improve performance
mount | grep "/tmp/clones" >/dev/null
if [[ $? -ne 0 && ! -d /tmp/clones ]]
then
    mkdir /tmp/clones
    sudo mount -t tmpfs -o size=2G,uid=`id -u`,gid=`id -g` tmpfs /tmp/clones
fi
cd /tmp/clones

time svnrdump dump http://googletest.googlecode.com/svn > gtest.svnrdump
time svnrdump dump http://googlemock.googlecode.com/svn > gmock.svnrdump

mkdir repos
(
    cd repos
    svnadmin create gtest
    time svnadmin load gtest < ../gtest.svnrdump
    svnadmin create gmock
    time svnadmin load gmock < ../gmock.svnrdump
)
svnserve --daemon --root repos

# TODO use a proper `--authors-file <file>` for the following two
#      `git shortlog --email -s' can help with that
time git svn clone --stdlayout svn://localhost/gtest gtest
time git svn clone --stdlayout svn://localhost/gmock gmock

# BEGIN gtest cleanup work
cd gtest

# create an annotated tag for each Subversion commit
# the tag message holds the Subversion PEG revision, e.g.
# svn://localhost/gtest/branches/release-1.2@166
git for-each-ref --sort='*authordate' --format='%(refname)' -- refs/remotes refs/heads/master | \
while read branch
do
    # TODO use `git rev-list'
    for rev in `git log --format='%H' --reverse ${branch}`
    do
        SVN_URI=`git log -1 --format='%B' ${rev} | sed -n 's#^git-svn-id: \(svn://localhost/gtest/.*\@[[:digit:]]\{1,3\}\) [[:xdigit:]]\{8\}-[[:xdigit:]]\{4\}.*$#\1#p'`
        SVN_REV=${SVN_URI##*@}
        git show svn-revisions/${SVN_REV} >/dev/null 2>&1
        if [ 0 -ne $? ]
        then
            echo ${SVN_URI} | git tag --annotate --file - svn-revisions/${SVN_REV} ${rev}
        else
            sha1=`git rev-parse svn-revisions/${SVN_REV}\^{commit}`
            if [ ${sha1} != ${rev} ]
            then
                echo "FATAL ${sha1} != ${rev}"
                break
            else
                continue
            fi
        fi
    done
done

# create actual git tags for all Subversion tags
# I opted to go with Linus' style of tag names (vMAJ.MIN{,.PATCH})
# instead of release-MAJ.MIN.PATH like done for gtest/gmock
# TODO these should point to a commit on trunk
git for-each-ref --format='%(refname)' -- refs/remotes/origin/tags | \
while read tag
do
    GIT_TAG=`echo ${tag} | sed \
        's/.*-\([[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\)/\1/'`
    IMPORTED_TAG=${tag##refs/}
    GIT_COMMITTER_DATE=`git log -1 "${IMPORTED_TAG}" --format='%cI'` \
    GIT_COMMITTER_NAME=`git log -1 "${IMPORTED_TAG}" --format='%cn'` \
    GIT_COMMITTER_EMAIL=`git log -1 "${IMPORTED_TAG}" --format='%ce'` \
        git tag -a "v${GIT_TAG}" ${IMPORTED_TAG} -m "v${GIT_TAG}"
done

# drop Subversion "tags"
git for-each-ref --format='%(refname)' -- refs/remotes/origin/tags | \
    xargs -n 1 git update-ref -d

# drop release branches - they are empty (TODO: not true)
git for-each-ref --format='%(refname)' -- 'refs/remotes/origin/release-*' | \
    xargs -n 1 git update-ref -d

# drop remaining Subversion branches
git update-ref -d refs/remotes/origin/trunk
# this one seems to be irrelevant - the Google engineers didn't keep it
git update-ref -d refs/remotes/origin/unsupported-vc6-port

# purge the 'git-svn-id:' line from each commit message
# this is taken verbatim from man git-filter-branch
git filter-branch --force --msg-filter '
       sed -e "/^git-svn-id:/d"
' --tag-name-filter cat -- --all

# TODO git filter-branch --force --prune-empty \
#    --tag-name-filter cat -- --all

# remove git-svn related stuff from .git/
rm -Rf .git/svn
# remove sections from .git/config that are related to Subversion
git config --local --remove-section "svn"
git config --local --remove-section "svn-remote.svn"

# TODO this would be the official (GitHub?) repository
git remote add origin git@github.com:obruns/gtest.git
git push origin master:master
git for-each-ref --format='%(refname)' -- 'refs/tags/v*' | \
while read tag
do
    git push origin ${tag}
done

# BEGIN gmock cleanup work
cd ../gmock

# we need to know the SHA-1 of `.gitmodules` so that we can add
# it to each commit later on
git submodule add https://github.com/obruns/gtest.git gtest
git diff-index HEAD | awk '/.gitmodules/ { print $4 }' > ../gitmodules.sha1
git reset --hard HEAD

# TODO this is duplicated from above (apart from 'svn://localhost/gmock)
#      come up with something more clever
git for-each-ref --sort='*authordate' --format='%(refname)' -- refs/remotes refs/heads/master | \
while read branch
do
    # TODO use `git rev-list'
    for rev in `git log --format='%H' --reverse ${branch}`
    do
        SVN_URI=`git log -1 --format='%B' ${rev} | sed -n 's#^git-svn-id: \(svn://localhost/gmock/.*\@[[:digit:]]\{1,3\}\) [[:xdigit:]]\{8\}-[[:xdigit:]]\{4\}.*$#\1#p'`
        SVN_REV=${SVN_URI##*@}
        git show svn-revisions/${SVN_REV} >/dev/null 2>&1
        if [ 0 -ne $? ]
        then
            echo ${SVN_URI} | git tag --annotate --file - svn-revisions/${SVN_REV} ${rev}
        else
            sha1=`git rev-parse svn-revisions/${SVN_REV}\^{commit}`
            if [ ${sha1} != ${rev} ]
            then
                echo "FATAL ${sha1} != ${rev}"
                break
            else
                continue
            fi
        fi
    done
done

# create actual git tags for all Subversion tags
# I opted to go with Linus' style of tag names (vMAJ.MIN{,.PATCH})
# instead of release-MAJ.MIN.PATH like done for gtest/gmock
# TODO these should point to a commit on trunk
git for-each-ref --format='%(refname)' -- refs/remotes/origin/tags | \
while read tag
do
    GIT_TAG=`echo ${tag} | sed \
        's/.*-\([[:digit:]]*\.[[:digit:]]*\.[[:digit:]]*\)/\1/'`
    IMPORTED_TAG=${tag##refs/}
    GIT_COMMITTER_DATE=`git log -1 "${IMPORTED_TAG}" --format='%cI'` \
    GIT_COMMITTER_NAME=`git log -1 "${IMPORTED_TAG}" --format='%cn'` \
    GIT_COMMITTER_EMAIL=`git log -1 "${IMPORTED_TAG}" --format='%ce'` \
        git tag -a "v${GIT_TAG}" ${IMPORTED_TAG} -m "v${GIT_TAG}"
done


# This will yield several errors of the following form
#   fatal: ambiguous argument 'svn-revisions/660': unknown revision or path not in the working tree.
# That is expected, those revisions are related to the wiki/ "branch"
# which has not been cloned. Revisions that are affected by this:
#
#   r325
#   r660
#   r687
#
# Currently, the previous reference is kept.
# TODO We need to walk backwards (325 - 1) and see if we could use that one.
git filter-branch --force --index-filter '
    OLD_CWD=`pwd`
    cd ../../
    revision=`git describe ${GIT_COMMIT}`
    URL=`git cat-file -p ${revision} | tail -1`
    EXTERNAL=`svn propget --strict svn:externals $URL`
    if [[ ! -z $EXTERNAL ]]
    then
        rm -Rf gtest
        rm -Rf .git/modules
        (
            cd ../gtest
            unset GIT_WORK_TREE
            unset GIT_DIR
            unset GIT_INDEX_FILE
            REVISION_TEMP=${EXTERNAL##gtest -r}
            REVISION=${REVISION_TEMP%% http*}
            SHA1=`git log -1 --format="%H" svn-revisions/$REVISION`
            if [[ ! -z $SHA1 ]]
            then
                echo $SHA1 > /tmp/sha-1
            fi
        )
        SHA1=`cat /tmp/sha-1`
        GITMODULES_SHA1=`cat ../gitmodules.sha1`
        git --git-dir .git/ ls-files -s > /tmp/index.$SHA1.before
        echo "0 0000000000000000000000000000000000000000	gtest
160000 ${SHA1} 0	gtest
100644 ${GITMODULES_SHA1} 0	.gitmodules" | git update-index --index-info
        git --git-dir .git/ ls-files -s > /tmp/index.$SHA1.after
    fi
    cd ${OLD_CWD}
' --tag-name-filter cat -- --all

# purge the 'git-svn-id:' line from each commit message
# this is taken verbatim from man git-filter-branch
git filter-branch --force --msg-filter '
       sed -e "/^git-svn-id:/d"
' --tag-name-filter cat -- --all

# you can easily run e.g. vimdiff on the history before and after --prune-empty
# there are some differences that can be easily explained via the commit messages
# Ignore .pyc files -- svn:ignore is a property, i.e. nothing that git sees
# Deletes the empty scons directory. -- git tracks content not files (empty dirs are irrelevant)
# Pull in gtest 687 -- this is a change to the wiki/ "branch" which is not part of the clone
git filter-branch --force --prune-empty \
    --tag-name-filter cat -- --all

# drop tags holding the Git<>Subversion relationship
git for-each-ref --format='%(refname)' -- 'refs/tags/svn-revisions/*' | \
    xargs -n 1 git update-ref -d

cd ../gtest
git for-each-ref --format='%(refname)' -- 'refs/tags/svn-revisions/*' | \
    xargs -n 1 git update-ref -d

# TODO ...

# WARNING: all work will be lost
# sudo umount /tmp/clones
