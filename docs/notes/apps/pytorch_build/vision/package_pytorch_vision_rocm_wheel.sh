if [ -z "$1" ]; then
    install_dir_prefix_rocm=/opt/rocm
    echo "No rocm_root_directory_specified, using default: ${install_dir_prefix_rocm}"
else
    install_dir_prefix_rocm=${1}
    echo "using rocm_root_directory specified: ${install_dir_prefix_rocm}"
fi
source ${install_dir_prefix_rocm}/bin/env_rocm.sh
export CMAKE_PREFIX_PATH=${install_dir_prefix_rocm}
FORCE_CUDA=1 TORCHVISION_USE_NVJPEG=0 TORCHVISION_USE_VIDEO_CODEC=0 CC=gcc CXX=g++ python setup.py bdist_wheel
