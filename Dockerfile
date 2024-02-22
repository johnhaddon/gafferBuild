# We start with `aswf/ci-base` as it provides a Rocky 8 environment that meets
# the glibc requirements of VFXPlatform 2023 (2.28 or lower), with many of our
# build dependencies already pre-installed.

FROM aswf/ci-base:2023.2

# Identify the build environment. This can be used by build processes for
# environment specific behaviour such as naming artifacts built from this
# container.
ENV GAFFER_BUILD_ENVIRONMENT="gcc11"

# As we don't want to inadvertently grab newer versions of our yum-installed
# packages, we use yum-versionlock to keep them pinned. We track the list of
# image packages here, then compare after our install steps to see what was
# added, and only lock those. This saves us storing redundant entires for
# packages installed in the base image.

# To unlock versions, just make sure yum-versionlock.list is empty in the repo
COPY versionlock.sh ./
COPY yum-versionlock.list /etc/yum/pluginconf.d/versionlock.list

RUN yum install -y 'dnf-command(versionlock)' && \
	./versionlock.sh list-installed /tmp/packages && \
#
#
# NOTE: If you add a new yum package here, make sure you update the version
# lock files as follows and commit the changes to yum-versionlock.list:
#
#   ./build-docker.py --update-version-locks --new-only
#
#	We install SCons via `pip install` rather than by
#	`yum install` because this prevents a Cortex build failure
#	caused by SCons picking up the wrong Python version and being
#	unable to find its own modules.
#
	pip install scons==4.6.0 && \
#
# Install packages needed to generate the
# Gaffer documentation.
#
	yum install -y \
		mesa-dri-drivers.x86_64 \
		metacity \
		gnome-themes-standard && \
# Note: When updating these, also update the MacOS setup in .github/workflows/main.yaml
# (in GafferHQ/gaffer).
	pip install \
		sphinx==4.3.1 \
		sphinxcontrib-applehelp==1.0.4 \
		sphinxcontrib-devhelp==1.0.2 \
		sphinxcontrib-htmlhelp==2.0.1 \
		sphinxcontrib-jsmath==1.0.1 \
		sphinxcontrib-serializinghtml==1.1.5 \
		sphinxcontrib-qthelp==1.0.3 \
		sphinx_rtd_theme==1.0.0 \
		myst-parser==0.15.2 \
		docutils==0.17.1 && \
#
# Install Inkscape 1.3.2
# Inkscape is distrubuted as an AppImage. AppImages seemingly can't be run (easily?) under
# Docker as they require FUSE, so we extract the image so its contents can be run directly.
	mkdir /opt/inkscape-1.3.2 && \
	cd /opt/inkscape-1.3.2 && \
	curl -O https://media.inkscape.org/dl/resources/file/Inkscape-091e20e-x86_64.AppImage && \
	chmod a+x Inkscape-091e20e-x86_64.AppImage && \
	./Inkscape-091e20e-x86_64.AppImage --appimage-extract && \
	ln -s /opt/inkscape-1.3.2/squashfs-root/AppRun /usr/local/bin/inkscape && \
	cd - && \
#
# Trim out a few things we don't need. We inherited a lot more than we need from
# `aswf/ci-base`, and we run out of disk space on GitHub Actions if our container
# is too big. A particular offender is CUDA, which comes with all sorts of
# bells and whistles we don't need, and is responsible for at least 5Gb of the
# total image size.
	rm -rf /var/opt/sonar-scanner-4.8.0.2856-linux && \
	dnf remove -y \
		cuda-nsight-compute-11-8.x86_64 \
		libcublas-devel-11-8-11.11.3.6-1.x86_64 && \
	dnf clean all && \
#
# Now we've installed all our packages, update yum-versionlock for all the
# new packages so we can copy the versionlock.list out of the container when we
# want to update the build env.
# If there were already locks in the list from the source checkout then the
# correct version will already be installed and we just ignore this...
	./versionlock.sh lock-new /tmp/packages

# Set WORKDIR back to / to match the behaviour of our CentOS 7 Dockerfile.
# This makes it easier to deal with copying build artifacts as they will be
# in the same location in both containers.
WORKDIR /

# ci-base sets PYTHONPATH, so we override it back to nothing for our env
ENV PYTHONPATH=
#
# Inkscape 1.3.2 prints "Setting _INKSCAPE_GC=disable as a workaround for broken libgc"
# every time it is run, so we set it ourselves to silence that
ENV _INKSCAPE_GC="disable"

# Make the Optix SDK available for Cycles builds.
ENV OPTIX_ROOT_DIR=/usr/local/NVIDIA-OptiX-SDK-7.3.0