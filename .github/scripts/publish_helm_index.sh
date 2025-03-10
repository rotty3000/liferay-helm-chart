#!/usr/bin/env bash
set -ev

tmpDir=$(mktemp -d)
pushd $tmpDir >& /dev/null

git clone ${REPO_URL}
cd ${REPOSITORY}
git checkout ${PUBLISH_BRANCH}

# Index the helm build chart and merge the index with the published one
helm repo index ${CHARTS_TMP_DIR} --url ${OCI_URL} --merge "${INDEX_DIR}/index.yaml"

# Copy the updated index over the previously published one
mv -f ${CHARTS_TMP_DIR}/index.yaml ${INDEX_DIR}/index.yaml

# Rewrite the urls into the correct OCI format
yq -i '.entries.liferay[].urls[] |= sub("-(\d+\.\d+\.\d+)\.tgz", ":$1")' ${INDEX_DIR}/index.yaml

# Copy the markdown files to the gh-pages branch
find . -name "*.md" -exec rm -f '{}' \;
if [ ! -d ./docs ]; then
	mkdir ./docs
fi
cp -R ${SOURCE_DIR}/docs/* ./docs
cp -R ${SOURCE_DIR}/README.md .
git add --all

# Diff for observability
echo "=== Start of Diff ==="
git -P diff --cached
echo "=== End of Diff ==="

# Commits need to be signed so we use the gh cli to ensure the changes are signed by `github-actions[bot]`
CHANGED=($(git -P diff --cached --name-only | xargs))

for value in "${CHANGED[@]}"
do
	if [ -f $value ]; then
		ADDITIONS="${ADDITIONS} -F additions[][path]=$value -F additions[][contents]=$(base64 -w0 $value)"
	else
		DELETIONS="${DELETIONS} -F deletions[][path]=$value"
	fi
done

if [ -z ${ADDITIONS+x} ]; then
	ADDITIONS="-F additions[]"
fi
if [ -z ${DELETIONS+x} ]; then
	DELETIONS="-F deletions[]"
fi

gh api graphql \
	-F githubRepository=${GIT_REPOSITORY} \
	-F branchName=${PUBLISH_BRANCH} \
	-F expectedHeadOid=$(git rev-parse HEAD) \
	-F commitMessage="github-actions[bot] commit updated helm index" \
	-F "query=@${SOURCE_DIR}/.github/api/createCommitOnBranch.gql" \
	${ADDITIONS} \
	${DELETIONS}

popd >& /dev/null
rm -rf $tmpDir
