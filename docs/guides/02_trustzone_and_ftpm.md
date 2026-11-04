# 보안 입문자를 위한 ARM TrustZone과 fTPM 2.0 가이드

> **문서 목적**: 소프트웨어 방어의 한계를 극복하는 ARM 하드웨어 격리 기술(TrustZone)의 원리와 OP-TEE 기반 펌웨어 TPM(fTPM 2.0) 및 RPMB 롤백 방지 스토리지의 동작 방식을 입문자 눈높이에서 알기 쉽게 설명함.  
> **대상 독자**: 시스템 보안 입문자, 리눅스 시스템 프로그래머, 임베디드 펌웨어 엔지니어  
> **상태**: Production Guide  

> [!TIP] 📽️ **세미나 발표 슬라이드 (Reveal.js Presentation)**
> 본 기술 가이드의 핵심 내용을 시각화한 대화형 전체화면 세미나 발표 슬라이드를 제공함:
> 👉 **[인터랙티브 슬라이드 쇼 열기 (`guide_02_trustzone_and_ftpm.html`)](/humanoid-sec-platform/presentations/guide_02_trustzone_and_ftpm.html)** (새 창 전체화면) | [📊 전체 발표자료 허브](/humanoid-sec-platform/presentations/index.html)  

---

## 1. 왜 소프트웨어만으로는 OS 해킹을 막을 수 없는가?

전통적인 컴퓨터 아키텍처에서는 운영체제(OS 커널, Ring 0)가 시스템의 모든 하드웨어와 메모리를 통제하는 전지전능한 존재였음.  
그러나 치명적인 문제가 존재함:

> **"만약 해커가 커널 취약점을 공격하여 커널 권한(Ring 0 / EL1)을 장악하면 어떻게 되는가?"**

커널이 뚫리는 순간 안티바이러스, 방화벽, 파일 접근 제어(SELinux/AppArmor) 등 모든 소프트웨어 보안 체계는 해커의 조작에 의해 손쉽게 무력화됨. 커널 자신이 오염되었기 때문에 커널 내부의 보안 프로그램은 자신이 해킹당했다는 사실조차 증명할 수 없음.

이 딜레마를 해결하기 위해 ARM은 **"OS 커널조차 절대 넘볼 수 없는 하드웨어 차원의 완벽한 격리 영역"**을 설계하였으며, 이것이 바로 **ARM TrustZone 기술**임.

---

## 2. ARM TrustZone 아키텍처: 두 개의 세계(Worlds)

TrustZone 기술의 핵심은 단일 CPU 코어와 버스를 논리적으로 쪼개어 **완전히 독립된 두 개의 물리적 실행 환경**을 만들어내는 것임:

[![ARM TrustZone World Switch](../diagrams/trustzone_world_switch.svg)](../diagrams/trustzone_world_switch.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](../diagrams/trustzone_world_switch.html)로 이동하여 Normal World와 Secure World 간 SMC 하드웨어 스위칭 구조 확인 가능.*

### 2.1. Normal World vs Secure World
1. **Normal World (일반 세계 - REE)**:
   - 우리가 흔히 사용하는 **Ubuntu 24.04 리눅스 커널(EL1)**과 **사용자 애플리케이션(EL0)**이 동작하는 영역임.
   - 복잡하고 거대한 소프트웨어가 구동되므로 언제든 취약점이 발생하고 해킹당할 수 있다고 가정(Zero-Trust)함.
2. **Secure World (보안 세계 - TEE)**:
   - 초경량 보안 운영체제인 **OP-TEE Core(S-EL1)**와 **신뢰 애플리케이션(Trusted Application - TA, S-EL0)**만이 동작함.
   - 외부 네트워크나 일반 디스크에 직접 노출되지 않고, 오직 신뢰할 수 있는 소형 암호화 로직만 실행됨.

### 2.2. 하드웨어 메모리 방화벽 (TZDRAM)
TrustZone 지원 SoC(NVIDIA Orin/Thor, ARM Cortex-A)의 메모리 컨트롤러는 하드웨어 **NS(Non-Secure) 비트**를 검사함:
- Normal World CPU가 메모리에 접근할 때 버스에는 `NS=1` 신호가 실림.
- 만약 Normal World가 Secure World 전용 메모리(TZDRAM, Secure SRAM) 주소를 읽거나 쓰려고 시도하면, **메모리 버스 하드웨어가 즉각 접근을 차단하고 하드웨어 버스 에러(Bus Fault)를 발생**시킴.
- 따라서 해커가 리눅스 커널의 최고 권한(루트)을 얻어 임의의 물리 메모리를 조작하더라도 Secure World 내부의 메모리는 단 1비트도 엿볼 수 없음.

### 2.3. 세계 전환: SMC (Secure Monitor Call)
Normal World가 Secure World의 기능을 사용하려면 일반 함수 호출로는 불가능하며, **`smc #0` (Secure Monitor Call)** 어셈블리 명령을 실행해야 함:
1. 리눅스 드라이버(`tee.ko`)가 레지스터에 파라미터를 채우고 `smc #0` 명령을 실행함.
2. CPU는 즉시 실행을 중단하고 최고 특권 모드인 **EL3 (TF-A Secure Monitor)**로 트랩됨.
3. TF-A가 CPU 레지스터를 백업하고 NS 비트를 0으로 바꾼 뒤 **Secure World (OP-TEE)**로 제어권을 넘김.
4. OP-TEE가 안전하게 작업을 마치면 다시 SMC를 통해 결과만 Normal World에 돌려줌.

---

## 3. dTPM(물리 칩) vs fTPM(펌웨어 TPM in OP-TEE)

신뢰 플랫폼 모듈(TPM: Trusted Platform Module)은 암호 연산과 시스템 무결성을 측정하는 표준 하드웨어임:

| 비교 항목 | 외장 dTPM (Discrete TPM) | OP-TEE fTPM (Firmware TPM) — 우리 플랫폼 |
| :--- | :--- | :--- |
| **구현 방식** | 보드 위에 납땜된 전용 독립 칩 (I2C/SPI 버스 연결) | ARM TrustZone Secure World 내부 소프트웨어 TA 구현 |
| **물리적 보안** | **스니핑 공격 취약**: I2C/SPI 버스에 로직 분석기를 대면 키 탈취 가능 | **버스 공격 불능**: 모든 연산이 SoC 내부 온칩(On-Chip) SRAM에서 수행됨 |
| **BOM 비용** | 추가 칩 비용 발생 ($2 ~ $5) | **$0 (추가 하드웨어 비용 없음, 순수 펌웨어 통합)** |
| **성능** | 느린 직렬 버스 속도로 인해 연산 지연 발생 | 초고속 온칩 메모리 속도로 수십 배 빠른 해시 연산 지원 |
| **표준 준수** | TCG TPM 2.0 표준 규격 완벽 준수 | TCG TPM 2.0 표준 준수 (`ms-tpm-20-ref` 공식 참조 구현) |

우리 플랫폼은 비용 절감과 물리적 버스 스니핑 공격 방어를 위해 **OP-TEE 내부의 `ms-tpm-20-ref` fTPM 2.0 TA**를 채택함.

---

## 4. TPM PCR 해시 연쇄와 무결성 측정의 원리

fTPM의 핵심 기능은 **PCR (Platform Configuration Register)**이라는 특수 레지스터를 통한 **시스템 무결성 해시 체이닝**임.

[![fTPM PCR 10 Hash-Chain](../diagrams/tpm_pcr_extend_flow.svg)](../diagrams/tpm_pcr_extend_flow.html)
> 💡 *클릭 시 [Archify 인터랙티브 뷰어](../diagrams/tpm_pcr_extend_flow.html)로 이동하여 PCR 10 해시 확장 및 원격 증명 챌린지 시퀀스 확인 가능.*

### 4.1. 왜 PCR은 값을 덮어쓸 수 없는가?
일반 CPU 레지스터는 `MOV PCR, 0`처럼 언제든 이전 값을 지우고 새 값을 쓸 수 있음.  
하지만 TPM PCR은 보안 설계상 **"쓰기(Overwrite)" 명령이 아예 존재하지 않음**. 오직 **"확장(Extend)"** 명령만 지원함:

$$\text{PCR}_{new} = \text{SHA-256}(\text{PCR}_{old} \parallel \text{Hash}(\text{실행된 바이너리}))$$

- 부팅 시 PCR 10은 0으로 초기화됨.
- 새로운 프로그램(예: `/usr/bin/actuator_node`)이 실행될 때마다 커널 IMA가 해당 바이너리의 해시를 PCR 10에 순차적으로 Extend함.
- **불가역성**: 한 번이라도 악성코드가 실행되면 PCR 10 값은 정상 기준값과 영원히 달라지며, 재부팅하지 않는 한 그 흔적을 지우거나 되돌리는 것이 수학적으로 불가능함.

---

## 5. RPMB (Replay Protected Memory Block)를 통한 안티롤백

보안 스토리지에서 가장 교묘한 공격은 **롤백 공격(Rollback / Replay Attack)**임.  
암호화된 파일이라도 해커가 "과거의 취약했던 버전의 암호문"으로 플래시 파티션을 덮어쓰면, 시스템은 정상 복호화에 성공하면서 구버전의 보안 결함 상태로 되돌아가게 됨.

이를 막기 위해 eMMC/UFS 플래시에는 **RPMB 하드웨어 파티션**이 내장되어 있음:
1. **공장 제조 단계 eFuse 키 공유**: RPMB 영역은 SoC 제조 시 eFuse에 기록된 비밀키와 플래시 메모리 컨트롤러만 공유하는 인증키(MAC)를 가짐.
2. **단조 증가 쓰기 카운터 (Write Counter)**: RPMB에 데이터를 쓸 때마다 플래시 내부 하드웨어 카운터가 1씩 증가함.
3. **재전송 차단**: 이전 카운터 값으로 작성된 오래된 암호문은 플래시 하드웨어가 즉각 쓰기를 거부함.

OP-TEE OS와 fTPM은 비휘발성 상태(NVRAM), 롤백 방지 카운터, 디바이스 비밀키를 모두 이 **RPMB 보안 스토리지(`CFG_RPMB_FS=y`)**에 안전하게 보관함.

---

## 6. 요약

- **ARM TrustZone**: Normal World(리눅스)가 완전히 장악되어도 Secure World(OP-TEE)의 메모리와 키는 물리적으로 침범할 수 없음.
- **fTPM 2.0**: 고가의 외장 칩 없이도 온칩 TrustZone 내부에서 물리 버스 스니핑 없는 TCG TPM 2.0 표준을 완벽히 제공함.
- **PCR 해시 체이닝**: 실행된 모든 소프트웨어의 해시가 비가역적으로 누적되어, 악성코드 실행 흔적을 숨길 수 없음.
- **RPMB 안티롤백**: 하드웨어 단조 카운터를 통해 소프트웨어 다운그레이드 공격을 원천 차단함.

