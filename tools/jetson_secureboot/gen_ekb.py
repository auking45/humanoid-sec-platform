#!/usr/bin/env python3

# SPDX-License-Identifier: BSD-2-Clause
# SPDX-FileCopyrightText: Copyright (c) 2021-2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.

# Version History
#
# 1.0: Initial version with T194 support
# 1.1: Add T234 support
# 1.2: Refactored EKB structure to make it more generic
# 1.3: Removed UEFI encryption and authentication keys from EKB (moved to MB2-BCT instead)
# 1.4: Support both OEM_K1 and OEM_K2 keys as the root key of EKB image (T234 only)
# 1.5: Add encoding fTPM serial number (SN), EPS seed and two fTPM EK Certificates (RSA and EC) support
# 1.6: Add encoding support for device Silicon ID certificate, fTPM RSA, and EC EK CSR
# 1.7: Remove T194 support
# 1.8: Add T264 support
#

import argparse
import codecs
import os.path
import struct
import sys

from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import cmac
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.kbkdf import (CounterLocation, KBKDFHMAC, Mode)
from math import ceil

# EKB verison number upgrade strategy
# Increment major version number when changing EKB header
# Increment minor version number when changing EKB content

# EKB version
# Version 1.0: Initial version
# Version 2.0: Add fv to the ekb header
# Version 2.1: FV is no longer used for T264, rename it to reserved. For T234, there is no change.
version_major = 2
version_minor = 1

# EKB key types
ekb_kernel_encryption_key = 1;
ekb_disk_encryption_key = 2;
ekb_uefi_var_auth_key = 4;
ekb_hwkey_app_key = 5;
ekb_ftpm_sn = 91;
ekb_ftpm_eps_seed = 92;
ekb_ftpm_rsa_ek_cert = 93;
ekb_ftpm_ec_ek_cert = 94;
ekb_sid_cert = 95;
ekb_ftpm_rsa_ek_csr = 96;
ekb_ftpm_ec_ek_csr = 97;

def pkcs7_padding(plain_text):
    block_size = 16  # AES block size is always 16 bytes
    number_of_bytes_to_pad = block_size - len(plain_text) % block_size
    padding_str = number_of_bytes_to_pad * bytes([number_of_bytes_to_pad])
    padded_plain_text =  plain_text + padding_str
    return padded_plain_text

def ekb_cmac_gen(key, msg):
    c = cmac.CMAC(algorithms.AES(key), backend=default_backend())
    c.update(msg)
    return c.finalize()

def ekb_encrypt(content, key, iv):
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    encryptor = cipher.encryptor()
    return encryptor.update(content) + encryptor.finalize()

def nist_sp_800_108_with_CMAC(key, context=b"", label=b"", len=16):
    okm = b""
    output_block = b""
    for count in range(ceil(len/16)):
        data = b"".join([bytes([count+1]), label.encode(encoding="utf8"), bytes([0]), context.encode(encoding="utf8"), int(len*8).to_bytes(4, byteorder="big")])
        c = cmac.CMAC(algorithms.AES(key), backend=default_backend())
        c.update(data)
        output_block = c.finalize()
        okm += output_block
    return okm[:len]

def nist_sp_800_108_with_KBKDF_HMAC_SHA256(key, label, context, len=32):
    kdf = KBKDFHMAC(
        algorithm=hashes.SHA256(),
        mode=Mode.CounterMode,
        length=32,
        rlen=4,
        llen=4,
        location=CounterLocation.BeforeFixed,
        label=label,
        context=context,
        fixed=None,
        backend=default_backend(),
    )
    return kdf.derive(key)

def gen_ekb_rk_t234(fuse_key, fv):
    cipher = Cipher(algorithms.AES(fuse_key), modes.ECB(), backend=default_backend())
    encryptor = cipher.encryptor()
    return encryptor.update(fv) + encryptor.finalize()

def gen_ekb_rk_t264(fuse_key):
    context = bytes([0])
    static_rt_kdk1 = nist_sp_800_108_with_KBKDF_HMAC_SHA256(fuse_key, b"STATIC_RT", context)
    static_rt_tz_kdk1 = nist_sp_800_108_with_KBKDF_HMAC_SHA256(static_rt_kdk1, b"STATIC_RT_TZ", context)
    return nist_sp_800_108_with_KBKDF_HMAC_SHA256(static_rt_tz_kdk1, b"ekb", b"root")

def generateBlob_t234(content, fuse_key):
    content_header_fmt = "<I4sxxxxxxxx"
    ekb_header_fmt = "<I8sHH"
    maxsize = 131072    # 128KB
    size = 0
    fv_len = 16
    ekb_header_len = 16
    ekb_header_wo_size_field = 12
    ekb_content_header_len = 16
    ekb_cmac_len = 16
    ekb_iv_len = 16
    contentmaxsize = maxsize - fv_len - ekb_header_len - ekb_content_header_len - ekb_cmac_len - ekb_iv_len

    # padding the content, then check the length after padding
    if (len(content) % 16) != 0:  # AES block size is 16 bytes
        content = pkcs7_padding(content)

    if len(content) > contentmaxsize:
        raise Exception("Content is too big")

    # generate a random fixed vector used to derive ekb root key.
    # the random fixed vector will also be stored in ekb.
    fv = os.getrandom(16, os.GRND_NONBLOCK)

    # generate root key for t234
    ekb_rk = gen_ekb_rk_t234(fuse_key, fv)

    # generate ekb ek and ak for t234
    key_ek = nist_sp_800_108_with_CMAC(ekb_rk, "ekb", "encryption")
    key_ak = nist_sp_800_108_with_CMAC(ekb_rk, "ekb", "authentication")

    # generate a random iv, then encrypt the key data content
    # join the iv and content header, calc cmac on the total data
    iv = os.getrandom(16, os.GRND_NONBLOCK)
    encrypted_content = ekb_encrypt(content, key_ek, iv)
    data = b"".join([iv, encrypted_content])
    content_header = struct.pack(content_header_fmt, len(encrypted_content), b"EEKB")
    data = b"".join([content_header, data])
    ekb_cmac = ekb_cmac_gen(key_ak, data)

    # if size is less than 1K, then padding it to 1024
    ekb_size = len(fv) + len(ekb_cmac) + len(content_header) + len(iv) + len(encrypted_content) + ekb_header_wo_size_field
    if ekb_size < 1024:
        pad_char = (1024 - ekb_size) % 256
        encrypted_content += bytes([pad_char]) * (1024 - ekb_size)

    # pack the ekb image with header
    eks_len = ekb_header_wo_size_field + len(fv) + len(ekb_cmac) + len(content_header) + len(iv) + len(encrypted_content)
    header = struct.pack(ekb_header_fmt, eks_len, b"NVEKBP\0\0", version_major, version_minor)
    blob = header + fv + ekb_cmac + content_header + iv + encrypted_content
    return blob

def generateBlob_t264(content, fuse_key):
    ekb_header_fmt = "<I8sHH"
    content_header_fmt = "<I4sxxxxxxxx"
    maxsize = 122880    # maxsize = eks_partition_size (128K) - bch_size (8K)
    size_of_ekb_len = 4
    ekb_header_len = 16
    ekb_reserved_len = 16
    ekb_reserved = bytes([0]) * (ekb_reserved_len)
    ekb_cmac_len = 16
    ekb_content_header_len = 16
    ekb_iv_len = 16
    contentmaxsize = maxsize - ekb_header_len - ekb_reserved_len - ekb_cmac_len - ekb_content_header_len - ekb_iv_len

    # padding the content, then check the length after padding
    if (len(content) % 16) != 0: # AES block size is 16 bytes
        content = pkcs7_padding(content)

    if len(content) > contentmaxsize:
        raise Exception("Content is too big")

    # generate root key for t264
    ekb_rk = gen_ekb_rk_t264(fuse_key)

    # generate ekb ek and ak for t264
    key_ek = nist_sp_800_108_with_KBKDF_HMAC_SHA256(ekb_rk, b"ekb", b"encryption")
    key_ak = nist_sp_800_108_with_KBKDF_HMAC_SHA256(ekb_rk, b"ekb", b"authentication")

    # generate a random iv, then encrypt the key data content, join the iv, calc cmac on the total data
    iv = os.getrandom(16, os.GRND_NONBLOCK)
    encrypted_content = ekb_encrypt(content, key_ek, iv)
    data = b"".join([iv, encrypted_content])
    content_header = struct.pack(content_header_fmt, len(encrypted_content), b"EEKB")
    data = b"".join([content_header, data])
    ekb_cmac = ekb_cmac_gen(key_ak, data)

    # if total size is less than 1K, then padding it to 1024
    total_ekb_size = ekb_header_len + ekb_reserved_len + len(ekb_cmac) + ekb_content_header_len  + len(iv) + len(encrypted_content)
    if total_ekb_size < 1024:
        pad_char = (1024 - total_ekb_size) % 256
        encrypted_content += bytes([pad_char]) * (1024 - total_ekb_size)
        total_ekb_size = 1024

    # ekb_len in the header
    ekb_len = total_ekb_size - size_of_ekb_len
    # pack the ekb image with header
    header = struct.pack(ekb_header_fmt, ekb_len, b"NVEKBP\0\0", version_major, version_minor)
    blob = header + ekb_reserved + ekb_cmac + content_header + iv + encrypted_content
    return blob

def load_file_check_size(f, size=16):
    with open(f, 'rb') as fd:
        content = fd.read().strip()
        content = content.decode('utf-8')
        if content.startswith(('0x', '0X')):
            key = codecs.decode(content[2:], 'hex')
        else:
            key = codecs.decode(content, 'hex')
        if len(key) != size:
            raise Exception("Wrong size")
        return key

def pack_key(f, tag):
    fmt = "<II"
    with open(f, 'rb') as fd:
        content = fd.read().strip()
        content = content.decode('utf-8')
        if content.startswith(('0x', '0X')):
            key = codecs.decode(content[2:], 'hex')
        else:
            key = codecs.decode(content, 'hex')
        key_header = struct.pack(fmt, tag, len(key))
        key_blob = key_header + key
        return key_blob

def pack_digits(digit_str, tag):
    fmt = "<II"
    digits_byte = bytes.fromhex(digit_str)
    digits_header = struct.pack(fmt, tag, len(digits_byte))
    digits_blob = digits_header + digits_byte
    return digits_blob

def pack_bin(f, tag):
    fmt = "<II"
    with open(f, "rb") as fd:
        bin = fd.read()
        bin_header = struct.pack(fmt, tag, len(bin))
        bin_blob = bin_header + bin
        return bin_blob

def main():
    parser = argparse.ArgumentParser(description='''
    Generates the EKB image by using OEM_K1/OEM_K2(for T234) or OEM_KDK1(for T264) derived key to encrypt user data.
    ''')

    parser.add_argument('-chip', nargs=1, required=False, help="specify chip: t234 or t264")
    parser.add_argument('-oem_k1_key', nargs=1, required=False, help="oem_k1 key (32 bytes) file in hex format [t234 only]")
    parser.add_argument('-oem_k2_key', nargs=1, required=False, help="oem_k2 key (32 bytes) file in hex format [t234 only]")
    parser.add_argument('-oem_kdk1_key', nargs=1, required=False, help="oem_kdk1 key (32 bytes) file in hex format [t264 only]")
    parser.add_argument('-in_sym_key', nargs=1, required=False, help="32-byte symmetric key file in hex format")
    parser.add_argument('-in_sym_key2', nargs=1, required=False, help="16-byte symmetric key file in hex format")
    parser.add_argument('-in_auth_key', nargs=1, required=False, help="16-byte symmetric key file in hex format")
    parser.add_argument('-in_hw_key', nargs=1, required=False, help="16-byte symmetric key file in hex format")
    parser.add_argument('-in_ftpm_sn', nargs=1, required=False, help="fTPM serial number")
    parser.add_argument('-in_ftpm_eps_seed', nargs=1, required=False, help="fTPM EPS seed file in hex format")
    parser.add_argument('-in_ftpm_rsa_ek_cert', nargs=1, required=False, help="fTPM RSA EK Cert in DER format")
    parser.add_argument('-in_ftpm_ec_ek_cert', nargs=1, required=False, help="fTPM EC EK Cert in DER format")
    parser.add_argument('-in_sid_cert', nargs=1, required=False, help="Device Silicon ID Cert in DER format")
    parser.add_argument('-in_ftpm_rsa_ek_csr', nargs=1, required=False, help="fTPM RSA EK CSR in DER format")
    parser.add_argument('-in_ftpm_ec_ek_csr', nargs=1, required=False, help="fTPM EK EK CSR in DER format")
    parser.add_argument('-out', nargs=1, required=True, help="where the eks image file is stored")

    args = parser.parse_args()

    if args.chip != None:
        chip = args.chip[0]
    else:
        raise Exception("chip cannot be empty")

    fuse_key_file = ""
    if chip == "t234":
        if args.oem_k1_key == None and args.oem_k2_key == None:
            raise Exception("No oem_k1_key or oem_k2_key is set.")
        if args.oem_k1_key != None and args.oem_k2_key != None:
            raise Exception("Only one oem key should be set.")

        if args.oem_k1_key != None and os.path.exists(args.oem_k1_key[0]):
            fuse_key_file = args.oem_k1_key[0]
        if args.oem_k2_key != None and os.path.exists(args.oem_k2_key[0]):
            fuse_key_file = args.oem_k2_key[0]

        if os.path.getsize(fuse_key_file) == 0:
            raise Exception("The oem_k1_key or oem_k2_key file is empty")

        if args.in_auth_key == None or not os.path.exists(args.in_auth_key[0]):
            print("WARNING: You must provided your own UEFI variable authentication key\n"
                  "when OEM key1 fuse is burned. Missing the UEFI variable authenticaton\n"
                  "key will cause the system to fail to boot up.")
            print("NOTE: If the board you are using is not fuse burned, you can ignore ths message.")
            input('Enter \'Ctrl + C\' to break, otherwise continue to generate EKB: ')
    elif chip == "t264":
        if args.oem_kdk1_key != None and os.path.exists(args.oem_kdk1_key[0]):
            fuse_key_file = args.oem_kdk1_key[0]
        else:
            raise Exception("The oem_kdk1_key is not set.")

        if os.path.getsize(fuse_key_file) == 0:
            raise Exception("The oem_kdk1_key file is empty")
    else:
        raise Exception("Invalid chip: " + chip)

    # load fuse key
    fuse_key = load_file_check_size(fuse_key_file, 32)

    # load and pack keys
    in_content = b""
    if args.in_sym_key != None and os.path.exists(args.in_sym_key[0]):
        in_content += pack_key(args.in_sym_key[0], ekb_kernel_encryption_key)
    if args.in_sym_key2 != None and os.path.exists(args.in_sym_key2[0]):
        in_content += pack_key(args.in_sym_key2[0], ekb_disk_encryption_key)
    if args.in_auth_key != None and os.path.exists(args.in_auth_key[0]):
        in_content += pack_key(args.in_auth_key[0], ekb_uefi_var_auth_key)
    if args.in_hw_key != None and os.path.exists(args.in_hw_key[0]):
        in_content += pack_key(args.in_hw_key[0], ekb_hwkey_app_key)
    if args.in_ftpm_sn != None:
        in_content += pack_digits(args.in_ftpm_sn[0], ekb_ftpm_sn)
    if args.in_ftpm_eps_seed != None and os.path.exists(args.in_ftpm_eps_seed[0]):
        in_content += pack_key(args.in_ftpm_eps_seed[0], ekb_ftpm_eps_seed)
    if args.in_ftpm_rsa_ek_cert != None and os.path.exists(args.in_ftpm_rsa_ek_cert[0]):
        in_content += pack_bin(args.in_ftpm_rsa_ek_cert[0], ekb_ftpm_rsa_ek_cert)
    if args.in_ftpm_ec_ek_cert != None and os.path.exists(args.in_ftpm_ec_ek_cert[0]):
        in_content += pack_bin(args.in_ftpm_ec_ek_cert[0], ekb_ftpm_ec_ek_cert)
    if args.in_sid_cert != None and os.path.exists(args.in_sid_cert[0]):
        in_content += pack_bin(args.in_sid_cert[0], ekb_sid_cert)
    if args.in_ftpm_rsa_ek_csr != None and os.path.exists(args.in_ftpm_rsa_ek_csr[0]):
        in_content += pack_bin(args.in_ftpm_rsa_ek_csr[0], ekb_ftpm_rsa_ek_csr)
    if args.in_ftpm_ec_ek_csr != None and os.path.exists(args.in_ftpm_ec_ek_csr[0]):
        in_content += pack_bin(args.in_ftpm_ec_ek_csr[0], ekb_ftpm_ec_ek_csr)

    # Padding key type and key len with 0 in the end
    end = struct.pack("xxxxxxxx")
    in_content += end

    # generate "eks.img"
    if chip == "t234":
        with open(args.out[0], 'wb') as f:
            f.write(generateBlob_t234(in_content, fuse_key))
    elif chip == "t264":
        with open(args.out[0], 'wb') as f:
            f.write(generateBlob_t264(in_content, fuse_key))
    else:
        raise Exception("Invalid chip: " + chip)

if __name__ == "__main__":
    main()

