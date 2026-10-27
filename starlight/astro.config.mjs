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
