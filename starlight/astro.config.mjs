import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import remarkMath from 'remark-math';
import rehypeKatex from 'rehype-katex';

const basePrefix = process.env.BASE_PATH ?? (process.env.GITHUB_ACTIONS ? '/humanoid-sec-platform' : '');

export default defineConfig({
  site: 'https://auking45.github.io',
  base: basePrefix || '/',
  prefetch: {
    prefetchAll: true,
    defaultStrategy: 'hover',
  },
  markdown: {
    remarkPlugins: [remarkMath],
    rehypePlugins: [rehypeKatex],
  },
  integrations: [
    {
      name: '@astrojs/sitemap',
      hooks: {},
    },
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
          label: '시작하기 (Getting Started)',
          items: [
            { label: '프로젝트 개요 (Overview)', link: '/' },
            { label: '빠른 시작 (Quick Start)', link: '/quick-start/' },
          ],
        },
        {
          label: '마스터 로드맵 (Roadmap)',
          items: [
            { label: '실행 체크리스트 (Roadmap Checklist)', link: '/roadmap-checklist/' },
          ],
        },
        {
          label: '보안 설계 및 명세서 (Design & Specs)',
          items: [
            { label: '시스템 아키텍처 (System Architecture)', link: '/architecture/' },
            { label: '보안 요구사항 정의서 (SRD)', link: '/requirements/' },
            { label: '키 관리 및 HSM / mTLS', link: '/key-management-hsm/' },
            { label: '위협 모델링 (Threat Model STRIDE)', link: '/threat-model/' },
          ],
        },
        {
          label: '인터랙티브 다이어그램 (Archify)',
          items: [
            { label: '다이어그램 갤러리 (Diagrams Gallery)', link: '/diagrams/' },
          ],
        },
      ],
    }),
  ],
});
