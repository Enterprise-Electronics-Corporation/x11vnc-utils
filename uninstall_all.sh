#!/bin/bash

# uninstall_all.sh - Uninstall all x11vnc-utils services and components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check for required scripts
if [ ! -f "./install_dufs.sh" ]; then
    print_warning "install_dufs.sh not found, skipping dufs uninstall."
else
    print_info "Uninstalling dufs file server..."
    sudo ./install_dufs.sh --uninstall || print_warning "dufs uninstall failed."
fi

if [ ! -f "./install_novnc.sh" ]; then
    print_warning "install_novnc.sh not found, skipping NoVNC uninstall."
else
    print_info "Uninstalling NoVNC web client..."
    sudo ./install_novnc.sh --uninstall || print_warning "NoVNC uninstall failed."
fi


if [ ! -f "./install_x11vnc_gdm_sddm_service.sh" ]; then
    print_warning "install_x11vnc_gdm_sddm_service.sh not found, skipping x11vnc uninstall."
else
    print_info "Uninstalling x11vnc service..."
    sudo ./install_x11vnc_gdm_sddm_service.sh --uninstall || print_warning "x11vnc uninstall failed."
fi

print_success "All uninstall operations complete."
