"""
tests/test_boot_optee.py — Automated QEMU, TF-A, OP-TEE & Kernel Verification Tests
"""

import os
import subprocess
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPTS_DIR = os.path.join(REPO_ROOT, "scripts")
CONFIGS_DIR = os.path.join(REPO_ROOT, "configs")


class TestPhase2KernelConfigs(unittest.TestCase):
    """Verifies that kernel configuration fragments meet SRD requirements."""

    def test_qemu_compat_config_presence_and_keys(self):
        config_path = os.path.join(CONFIGS_DIR, "kernel", "qemu_compat.config")
        self.assertTrue(os.path.isfile(config_path), f"Missing {config_path}")

        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_symbols = [
            "CONFIG_ARM_GIC_V3=y",
            "CONFIG_SERIAL_AMBA_PL011=y",
            "CONFIG_SERIAL_AMBA_PL011_CONSOLE=y",
            "CONFIG_VIRTIO=y",
            "CONFIG_VIRTIO_PCI=y",
            "CONFIG_VIRTIO_BLK=y",
            "CONFIG_VIRTIO_NET=y",
            "CONFIG_HW_RANDOM_VIRTIO=y",
            "CONFIG_BLK_DEV_INITRD=y",
        ]
        for sym in required_symbols:
            self.assertIn(sym, content, f"Missing required hardware driver symbol: {sym}")

    def test_security_hardening_config_presence_and_keys(self):
        config_path = os.path.join(CONFIGS_DIR, "kernel", "security_hardening.config")
        self.assertTrue(os.path.isfile(config_path), f"Missing {config_path}")

        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_symbols = [
            # Memory hardening (SRD-KRN-001)
            "CONFIG_STRICT_KERNEL_RWX=y",
            "CONFIG_ARM64_PAN=y",
            "CONFIG_STACKPROTECTOR_STRONG=y",
            "CONFIG_RANDOMIZE_BASE=y",
            # Module signing (SRD-KRN-002)
            "CONFIG_MODULE_SIG=y",
            "CONFIG_MODULE_SIG_FORCE=y",
            # Attack surface (SRD-KRN-003)
            "CONFIG_STRICT_DEVMEM=y",
            # OP-TEE & fTPM (SRD-TEE-001, SRD-TEE-002)
            "CONFIG_TEE=y",
            "CONFIG_OPTEE=y",
            "CONFIG_TCG_FTPM_TEE=y",
            # Storage integrity (SRD-STR-001, SRD-STR-002)
            "CONFIG_EROFS_FS=y",
            "CONFIG_DM_VERITY=y",
            # IMA (SRD-INT-001, SRD-INT-002)
            "CONFIG_IMA=y",
            "CONFIG_IMA_MEASURE_PCR_IDX=10",
        ]
        for sym in required_symbols:
            self.assertIn(sym, content, f"Missing required security hardening symbol: {sym}")


class TestPhase2OpteeConfigs(unittest.TestCase):
    """Verifies that OP-TEE configuration meets cryptographic & RPMB requirements."""

    def test_optee_conf_presence_and_keys(self):
        config_path = os.path.join(CONFIGS_DIR, "optee", "ftpm_pkcs11.conf")
        self.assertTrue(os.path.isfile(config_path), f"Missing {config_path}")

        with open(config_path, "r", encoding="utf-8") as f:
            content = f.read()

        required_symbols = [
            "CFG_ARM64_core=y",
            "CFG_PKCS11_TA=y",
            "CFG_RPMB_FS=y",
            "CFG_EARLY_TA=y",
            "CFG_REE_FS=y",
        ]
        for sym in required_symbols:
            self.assertIn(sym, content, f"Missing required OP-TEE build option: {sym}")


class TestPhase2ScriptsExecution(unittest.TestCase):
    """Verifies CLI flags, dry-run capabilities, and output generation."""

    def test_fetch_l4t_sources_dry_run(self):
        script = os.path.join(SCRIPTS_DIR, "fetch_l4t_sources.sh")
        result = subprocess.run([script, "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("public_sources.tbz2", result.stdout)
        self.assertIn("Jetson_Linux", result.stdout)

    def test_build_kernel_dry_run(self):
        script = os.path.join(SCRIPTS_DIR, "build_kernel.sh")
        result = subprocess.run([script, "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("Dual-Target Architecture", result.stdout)
        self.assertIn("security_hardening.config", result.stdout)
        self.assertIn("qemu_compat.config", result.stdout)

    def test_build_tfa_optee_dry_run(self):
        script = os.path.join(SCRIPTS_DIR, "build_tfa_optee.sh")
        result = subprocess.run([script, "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertIn("QEMU ARMv8-A virt", result.stdout)
        self.assertIn("ftpm_pkcs11.conf", result.stdout)

    def test_run_qemu_dry_run_parameters(self):
        script = os.path.join(SCRIPTS_DIR, "run_qemu.sh")
        result = subprocess.run([script, "--dry-run"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        cmdline = result.stdout
        # Machine flags
        self.assertIn("virt,secure=on,gic-version=3", cmdline)
        self.assertIn("cortex-a57", cmdline)
        # Kernel & console flags
        self.assertIn("console=ttyAMA0", cmdline)
        self.assertIn("earlycon=pl011", cmdline)
        # Security params
        self.assertIn("ima_policy=tcb", cmdline)
        self.assertIn("ima_hash=sha256", cmdline)
        # Network forward ports
        self.assertIn("2222", cmdline)
        self.assertIn("8443", cmdline)

    def test_run_qemu_missing_binary_preflight(self):
        script = os.path.join(SCRIPTS_DIR, "run_qemu.sh")
        env = os.environ.copy()
        env["QEMU_BIN"] = "nonexistent-qemu-binary-test"
        result = subprocess.run([script], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 127)
        self.assertIn("was not found in PATH", result.stdout + result.stderr)

    def test_humanoid_master_cli_modes(self):
        cli = os.path.join(REPO_ROOT, "humanoid.sh")
        self.assertTrue(os.path.isfile(cli))
        self.assertTrue(os.access(cli, os.X_OK))

        res_status = subprocess.run([cli, "status"], capture_output=True, text=True)
        self.assertEqual(res_status.returncode, 0)
        self.assertIn("Readiness Dashboard", res_status.stdout)

        res_flash = subprocess.run([cli, "flash-hardware", "status"], capture_output=True, text=True)
        self.assertEqual(res_flash.returncode, 0)
        self.assertIn("Hardware Deployment Staging Dashboard", res_flash.stdout)

        res_dry = subprocess.run([cli, "all", "--ubuntu", "--dry-run"], capture_output=True, text=True)
        self.assertEqual(res_dry.returncode, 0)
        self.assertIn("[STEP 1]", res_dry.stdout)
        self.assertIn("[STEP 2]", res_dry.stdout)
        self.assertIn("[STEP 3]", res_dry.stdout)


if __name__ == "__main__":
    unittest.main()

