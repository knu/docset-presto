#!/bin/sh

set -e

if [ -d presto/.git ]; then
    (cd presto && git remote update)
else
    git clone https://github.com/prestodb/presto.git presto
fi

version="${1:-current}"

case "$version" in
    current)
        tag=$(cd presto && git tag --sort=-version:refname | awk '/^[0-9.]+$/ { print; exit }')
        ;;
    *)
        tag=$version
esac

echo "Building documentation for version $tag"
(cd presto && git checkout "$tag")

docker build -f Dockerfile.sphinx -t presto-docs-sphinx .

target=prestodb.io/docs/"$version"
mkdir -p "$target"

docker run --rm \
       -v $(pwd)/presto/presto-docs:/docs/presto-docs \
       -v $(pwd)/requirements.txt:/docs/requirements.txt:ro \
       -w /docs/presto-docs/src/main/sphinx \
       presto-docs-sphinx \
       sphinx-build -b html . /docs/presto-docs/target

rsync -rpt --delete \
      --exclude '_static/_templates/' \
      --exclude '_static/**/*.{py,rst,fragment}' \
      --exclude '_sources/' \
      --exclude '.doctrees/' \
      --exclude '.buildinfo' \
      presto/presto-docs/target/ "$target"/

echo "Documentation built successfully in $target"
