# 보안 입문자를 위한 리눅스 커널 하드닝 가이드

> **문서 목적**: 운영체제의 심장부인 리눅스 커널(Ring 0 / EL1)의 권한 구조와 해커들이 왜 커널 장악을 노리는지, 그리고 KSPP(Kernel Self-Protection Project)와 모듈 서명 강제를 통해 커널 침해를 원천 차단하는 기술적 원리를 입문자 눈높이에서 알기 쉽게 설명함.  
> **대상 독자**: 시스템 보안 입문자, 리눅스 커널/드라이버 개발자, 로봇 시스템 소프트웨어 엔지니어  
> **상태**: Production Guide  

> [!TIP] 📽️ **세미나 발표 슬라이드 (Reveal.js Presentation)**
> 본 기술 가이드의 핵심 내용을 시각화한 대화형 전체화면 세미나 발표 슬라이드를 제공함:
> 👉 **[인터랙티브 슬라이드 쇼 열기 (`guide_03_linux_kernel_hardening.html`)](/humanoid-sec-platform/presentations/guide_03_linux_kernel_hardening.html)** (새 창 전체화면) | [📊 전체 발표자료 허브](/humanoid-sec-platform/presentations/index.html)  

---

## 1. 운영체제의 심장: Ring 3 vs Ring 0

CPU 하드웨어는 권한 수준(Privilege Levels)에 따라 실행 모드를 엄격히 분리함:

```text
+--------------------------------------------------------------+
|  User Space (Ring 3 / EL0)                                   |
|  - 사용자 프로그램: ROS 2 노드, Python 제어 스크립트, 웹 브라우저 |
|  - 제한 사항: 하드웨어 직접 접근 불가, CPU 특권 명령 실행 불가   |
+--------------------------------------------------------------+
                               |  시스템 콜 (syscall) 인터페이스
                               v
+--------------------------------------------------------------+
|  Kernel Space (Ring 0 / EL1)                                 |
|  - 리눅스 커널: 프로세스 스케줄러, 메모리 관리자, 디바이스 드라이버 |
|  - 권한: 모든 물리 메모리 읽기/쓰기, 모터/센서 제어, I/O 제어   |
+--------------------------------------------------------------+
```

1. **Ring 3 (사용자 공간)**: 일반적인 응용 프로그램이 구동되는 영역임. 버그나 악성코드로 인해 프로세스가 크래시되어도 해당 프로세스 하나만 종료될 뿐 전체 시스템은 영향을 받지 않음.
2. **Ring 0 (커널 공간)**: 하드웨어의 모든 물리 자원을 직접 통제하는 최상위 특권 영역임.

---

## 2. 해커는 왜 기를 쓰고 링 0(커널)를 노리는가?

일반적인 해킹은 사용자 영역(웹 서버, 네트워크 데몬)의 취약점을 통해 "일반 사용자(UID 1000)" 권한을 얻는 것으로 시작함.  
그러나 일반 사용자 권한으로는 할 수 있는 일이 제한적임:

- 시스템 중요 설정 파일을 수정할 수 없음.
- 다른 프로세스의 메모리를 훔쳐볼 수 없음.
- 안티바이러스나 보안 로깅을 끌 수 없음.

따라서 해커의 핵심 목표는 **"권한 상승(Privilege Escalation)"**을 통해 **Ring 0 커널을 장악**하는 것임. 커널이 장악되면:
- **물리적 위협**: 로봇의 모터 토크 제한이나 안전 감지 센서를 무력화하여 로봇이 사람을 가격하도록 오작동 유도 가능.
- **완벽한 은닉 (Stealth Rootkit)**: `ps`, `ls`, `netstat` 등 관리 도구에서 악성 프로세스와 네트워크 연결을 감쪽같이 숨겨 시스템 관리자가 침해 사실을 전혀 눈치채지 못하게 만듦.
- **모든 보안 소프트웨어 무력화**: SELinux, eBPF 모니터링, 방화벽 규칙을 메모리 레벨에서 직접 0으로 덮어써서 비활성화함.

---

## 3. 다계층 방어: KSPP (Kernel Self-Protection Project)

커널 하드닝은 단 하나의 마법 같은 기술이 아니라, 공격자의 공격 경로마다 장벽을 세우는 **심층 방어(Defense-in-Depth)** 체계임:

[![Kernel Hardening Layers](../diagrams/kernel_hardening_layers.svg)](../diagrams/kernel_hardening_layers.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](../diagrams/kernel_hardening_layers.html)로 이동하여 EL0부터 TrustZone까지의 다계층 보안 하드닝 구조 확인 가능.*

우리 플랫폼은 리눅스 커널 공식 보안 프로젝트인 **KSPP 권고안**을 기반으로 다음 핵심 하드닝을 적용함:

### 3.1. 물리 메모리 직접 접근 차단: `/dev/mem` 봉쇄
- **공격 방식**: 과거 리눅스에서는 루트 권한을 가진 프로세스가 `/dev/mem` 또는 `/dev/kmem` 특수 파일을 열어 전체 물리 메모리를 임의로 읽고 쓸 수 있었음. 이를 통해 커널 코드를 실시간으로 덮어써서 루트킷을 주입함.
- **하드닝 설정**:
  ```ini
  CONFIG_STRICT_DEVMEM=y
  CONFIG_IO_STRICT_DEVMEM=y
  ```
- **방어 효과**: 루트 사용자라도 시스템 RAM 영역에 대한 직접 접근이 하드웨어 수준에서 차단되며, 오직 승인된 I/O 디바이스 레지스터 매핑만 허용됨.

### 3.2. 메모리 공격 완화: KASLR과 스택 보호
- **KASLR (Kernel Address Space Layout Randomization)**: 부팅할 때마다 커널 코드와 데이터 구조체가 배치되는 물리 메모리 주소를 무작위로 섞음. 공격자가 미리 계산된 고정 주소로 점프하여 셸코드를 실행하는 ROP(Return-Oriented Programming) 공격을 무력화함.
- **스택 카나리아 (Stack Protector)**: 함수 복귀 주소(Return Address) 앞에 특수한 난수값(카나리아)을 삽입하여, 버퍼 오버플로우 공격으로 복귀 주소가 변조되는 순간 커널 패닉을 일으켜 공격 코드 실행을 사전에 차단함.

---

## 4. 커널 모듈 서명 강제 (`CONFIG_MODULE_SIG_FORCE=y`)

리눅스 커널은 새로운 하드웨어를 지원하기 위해 런타임에 동적으로 드라이버 코드인 **커널 모듈(`.ko`)**을 적재(`insmod`, `modprobe`)할 수 있음.  
해커는 이 기능을 악용하여 직접 작성한 악성 루트킷(`.ko`)을 커널에 적재하려고 시도함.

우리 플랫폼은 이를 막기 위해 **디지털 서명이 검증되지 않은 모듈의 적재를 100% 거절**하는 설정을 강제함:

```ini
CONFIG_MODULE_SIG=y
CONFIG_MODULE_SIG_FORCE=y
CONFIG_MODULE_SIG_ALL=y
CONFIG_MODULE_SIG_SHA256=y
```

```text
[공격자의 위조 모듈 적재 시도]
Attacker  --insmod rootkit.ko-->  Linux Kernel (EL1)
                                      |
                                      +--> PKCS#7 서명 블록 검사
                                      |    - 서명 없음? -> 즉각 차단! (ENOEXEC)
                                      |    - 모듈 내용이 1바이트라도 변조됨? -> 즉각 차단!
                                      |    - 빌트인 키링에 등록된 공개키로 검증 성공? -> 적재 허용
```

모듈 서명에 사용되는 개인키(`KernelModuleSigningKey`, RSA-3072)는 앞선 가이드에서 설명한 **SoftHSMv2 토큰 내부에 격리**되어 있으므로, 공격자는 유효한 서명을 절대 위조할 수 없음.

---

## 5. eBPF 보안: 비인가(Unprivileged) eBPF 차단

최신 리눅스 커널의 강력한 기능인 **eBPF(Extended Berkeley Packet Filter)**는 사용자 공간에서 작성한 바이트코드를 커널 내부의 가상머신(JIT)에서 고속으로 실행할 수 있게 해줌.  
하지만 eBPF는 최근 수많은 커널 익스플로잇(Spectre 사이드채널 공격, 커널 메모리 임의 읽기/쓰기)의 주요 통로로 악용되고 있음:

우리 플랫폼은 루트가 아닌 일반 사용자의 eBPF 실행을 원천 금지함:

```ini
CONFIG_BPF_UNPRIV_DEFAULT_OFF=y
```
```bash
# 런타임 sysctl 강제 설정
sysctl -w kernel.unprivileged_bpf_disabled=1
```

이를 통해 일반 애플리케이션 계정이 eBPF 명령을 호출하는 순간 커널은 `EPERM (Permission Denied)` 에러를 반환하며 즉각 실행을 거절함.

---

## 6. 요약

1. **커널(Ring 0)의 중요성**: 커널이 뚫리면 모든 소프트웨어 보안 체계는 의미가 없어지므로, 커널 자체의 자기 방어(KSPP)가 필수적임.
2. **물리 메모리 보호**: `CONFIG_STRICT_DEVMEM`으로 `/dev/mem`을 봉쇄하여 런타임 메모리 패칭 공격을 차단함.
3. **모듈 서명 강제**: `CONFIG_MODULE_SIG_FORCE`를 통해 미서명 루트킷(`.ko`)의 커널 침투를 100% 방어함.
4. **eBPF 비인가 차단**: 악용 가능성이 높은 커널 JIT 기능에 일반 프로세스가 접근하지 못하도록 통제함.

