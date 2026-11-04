import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

const basePrefix = process.env.BASE_PATH ?? '/humanoid-sec-platform';

export default defineConfig({
  site: 'https://auking45.github.io',
  base: basePrefix,
  prefetch: {
    prefetchAll: true,
    defaultStrategy: 'hover',
  },
  markdown: {
    remarkPlugins: [remarkMath],
    rehypePlugins: [rehypeKatex],
  },
  integrations: [
    starlight({
      title: 'Humanoid Security Platform',
      tagline: 'QEMU & L4T Security Verification for NVIDIA Jetson Humanoid Robots',
      social: {
        github: 'https://github.com/auking45/humanoid-sec-platform',
      },
      defaultLocale: 'root',
      locales: {
        root: {
          label: '한국어',
          lang: 'ko',
        },
        en: {
          label: 'English',
          lang: 'en',
        },
      },
      customCss: ['./src/styles/custom.css'],
      head: [
        {
          tag: 'link',
          attrs: {
            rel: 'stylesheet',
            href: 'https://cdn.jsdelivr.net/gh/orioncactus/pretendard@v1.3.9/dist/web/variable/pretendardvariable-dynamic-subset.min.css',
          },
        },
        {
          tag: 'link',
          attrs: {
            rel: 'stylesheet',
            href: 'https://fonts.googleapis.com/css2?family=JetBrains+Mono:ital,wght@0,400..700;1,400..700&display=swap',
          },
        },
      ],
      sidebar: [
        {
          label: '시작하기',
          translations: { en: 'Getting Started' },
          items: [
            { label: '빠른 시작 가이드', translations: { en: 'Quick Start Guide' }, slug: 'quick-start' },
            { label: 'E2E 검증 & 공격 실습 가이드', translations: { en: 'E2E Verification & Attack Lab' }, slug: 'e2e-verification-guide' },
            { label: '공격 시나리오 및 다계층 방어 가이드', translations: { en: 'Attack Scenarios & Defense Guide' }, slug: 'attack-defense-guide' },
            { label: '물리 보드 배포 & 플래싱', translations: { en: 'Hardware Deployment & Flashing' }, slug: 'hardware-deployment-guide' },
          ],
        },
        {
          label: '마스터 로드맵',
          translations: { en: 'Master Roadmap' },
          items: [
            { label: '실행 체크리스트', translations: { en: 'Roadmap Checklist' }, slug: 'roadmap-checklist' },
          ],
        },
        {
          label: '보안 입문 & 핵심 기술 가이드',
          translations: { en: 'Beginner & Technology Guides' },
          items: [
            { label: '01. 키 관리와 PKCS#11 (Zero-Key)', translations: { en: '01. Key Management & PKCS#11' }, slug: 'guides/01-key-management-and-pkcs11' },
            { label: '02. ARM TrustZone & fTPM 2.0', translations: { en: '02. ARM TrustZone & fTPM 2.0' }, slug: 'guides/02-trustzone-and-ftpm' },
            { label: '03. 리눅스 커널 하드닝 (KSPP)', translations: { en: '03. Linux Kernel Hardening' }, slug: 'guides/03-linux-kernel-hardening' },
            { label: '04. 스토리지 무결성 (Merkle/verity)', translations: { en: '04. Storage Integrity (dm-verity)' }, slug: 'guides/04-storage-integrity-verity' },
            { label: '05. 런타임 원격 증명 & mTLS', translations: { en: '05. Runtime Attestation & mTLS' }, slug: 'guides/05-runtime-attestation-and-mtls' },
          ],
        },
        {
          label: '보안 설계 및 명세서',
          translations: { en: 'Design & Specifications' },
          items: [
            { label: '시스템 아키텍처', translations: { en: 'System Architecture' }, slug: 'architecture' },
            { label: '보안 요구사항 정의서 (SRD)', translations: { en: 'Security Requirements (SRD)' }, slug: 'requirements' },
            { label: '키 관리 및 HSM / mTLS', translations: { en: 'Key Management & HSM / mTLS' }, slug: 'key-management-hsm' },
            { label: '위협 모델링 (STRIDE)', translations: { en: 'Threat Modeling (STRIDE)' }, slug: 'threat-model' },
          ],
        },
        {
          label: '엔지니어링 상세 규격서 (Features)',
          translations: { en: 'Feature Deep-Dives' },
          items: [
            { label: '01. Secure Boot & UEFI db', translations: { en: '01. Secure Boot & UEFI db' }, slug: 'features/01-secure-boot-uefi' },
            { label: '02. TrustZone & fTPM 2.0', translations: { en: '02. TrustZone & fTPM 2.0' }, slug: 'features/02-trustzone-optee-ftpm' },
            { label: '03. Kernel Hardening & Module Sign', translations: { en: '03. Kernel Hardening & Module Sign' }, slug: 'features/03-kernel-hardening-kspp' },
            { label: '04. EROFS + dm-verity + OverlayFS', translations: { en: '04. EROFS + dm-verity + OverlayFS' }, slug: 'features/04-storage-integrity-verity' },
            { label: '05. IMA PCR 10 & Remote Attestation', translations: { en: '05. IMA PCR 10 & Remote Attestation' }, slug: 'features/05-runtime-attestation-ima' },
            { label: '06. Zero Key & TLS 1.3 mTLS', translations: { en: '06. Zero Key & TLS 1.3 mTLS' }, slug: 'features/06-zero-key-management-mtls' },
          ],
        },
        {
          label: '인터랙티브 다이어그램',
          translations: { en: 'Archify Diagrams' },
          items: [
            { label: '다이어그램 갤러리', translations: { en: 'Diagrams Gallery' }, slug: 'diagrams' },
          ],
        },
      ],
    }),
  ],
});
