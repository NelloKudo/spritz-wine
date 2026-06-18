#!/usr/bin/env bash

## Script to launch the build process in the Docker container.

Info() {
    echo -e '\033[1;34m'"WineBuilder:\033[0m $*"
}

Info "Welcome to WineBuilder!"

## Setting up Docker..
mkdir -p {ccache,output,sources}

Info "Pulling Docker image..."
docker pull nellokudo/wine-builder:steamrt4-190426 || { echo "docker pull failed" && exit 1; }
docker tag nellokudo/wine-builder:steamrt4-190426 wine-builder:latest

# Or build the image locally from the Dockerfile
# docker buildx build --progress=plain -t wine-builder . || { echo "docker build failed" && exit; }

## Allow overriding variables in wine_builder.sh
vars=(USE_STAGING USE_TKG BUILD_NAME \
      WINE_BRANCH PATCHSET PATCHSET_REPO TAG_FILTER)

WB_ENV_ARGS=()
for var in "${vars[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        WB_ENV_ARGS+=(-e "$var=${!var}")
    fi
done

## Building..
chmod +x wine_builder.sh
docker run --rm \
    --name wine-builder \
    --security-opt label=disable \
    "${WB_ENV_ARGS[@]}" \
    --mount type=bind,source="$(pwd)"/wine_builder.sh,target=/usr/local/bin/wine_builder.sh \
    --mount type=bind,source="$(pwd)"/output,target=/wine \
    --mount type=bind,source="$(pwd)"/assets,target=/wine/assets \
    --mount type=bind,source="$(pwd)"/patches,target=/wine/custompatches \
    --mount type=bind,source="$(pwd)"/ccache,target=/root/.ccache \
    --mount type=bind,source="$(pwd)"/sources,target=/wine/sources \
    --entrypoint "/usr/local/bin/wine_builder.sh" \
    wine-builder "$@" || { echo "wine build failed" && exit; }

Info "FIXME: fixing up ownership of build files..."
sudo chown -R "$(id -u)":"$(id -g)" output/

## Copying finished builds in main directory..
mv output/*.tar.* .
