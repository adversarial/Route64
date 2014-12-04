;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Implements several routines to "break  through" the WoW64 layer.
;; by ~vividrev
;;
;; 12/3/14:
;;      0.1: It works
;;
; todo list:
;      refactor
;      fix internal errors (register scrapping)

include '%inc%\win32a.inc'
format MS COFF

CS_MODE_WOW64 = $23
CS_MODE_NATIVE_AMD64 = $33


public WoW64Write64 as '_WoW64Write64@16'
public WoW64Read64 as '_WoW64Read64@16'
public WoW64Stdcall64 as '_WoW64Stdcall64@16'

;======= Code ===================================
section '.text' code readable executable align 16
;================================================
use32
; size_t __stdcall xx(uchar* DestLow, uchar* DestHigh,
;                     const uchar* Src, size_t cbSrc)
WoW64Write64:
	push ebx
	push esi
	lea eax, [esp+$c]	 ; args[]
	stdcall WoW64Stdcall64, x64Write,\  ; DestLow => Dest
				 0,\	; DestHigh=> our code is in 32 bit space
				 4*4,\	; cb_args => sizeof(args)
				 eax	; args&   => &args[Src]

	pop esi
	pop ebx
	ret 4*4

; size_t __stdcall xx(const uchar* SrcLow, const uchar* SrcHigh,
;                     uchar* Dest, size_t cbDest)
WoW64Read64:
	push ebx	; random functions save random registers
	push esi	; todo: refactor

	lea eax, [esp+$c]		    ; args[]
	stdcall WoW64Stdcall64, x64Read,\  ; DestLow => Dest
				 0,\	; DestHigh=> our code is in 32 bit space
				 4*4,\	; cb_args => sizeof(args)
				 eax	; args&   => &args[Dest]
	pop esi
	pop ebx
	ret 4*4

; uint32_t __cdecl xx(uintptr_t AddrLow, uintptr_t AddrHigh, uint args_cb, void** args)
WoW64Stdcall64:
	push ebp
	push edi
	push esi

	; Ensure we are in WoW64 mode
	xor ecx, ecx
	not ecx
	mov eax, cs
	cmp eax, CS_MODE_WOW64
	cmovne eax, ecx 	; return -1
	jne .Done

	mov ecx, [esp+4*3+4+4*2]	; args_cb
	shr ecx, 2			; args_cb / sizeof(arg) = num args
	mov esi, [esp+4*3+4+4*3]	; args[]
	lea esi, [esi+ecx*4-4]		; advance to end of args, -4 to account for non-0index

	xor eax, eax
	xor edx, edx

	; allocate space for saved registers in x64 mode, because we want to construct
	; a call and leave the stack intact
	; padding may be added, so this allocation may not necessarily be a pointer
	sub esp, 8*3

	; if num_args is even, we need to push an extra qword for alignment due
	; to our own implicit padding arg, plus 2 extra (callee and num_args)
	; if it's odd, the stack will be automatically aligned to 16
	test ecx, 1
	setz dl
	shl edx, 3		; if num_args is odd, eax = 8 else eax = 0
	; align stack to 8
	; cb of alignment is pushed as qword
	mov eax, esp		; lower 2 bits should never be set in x86-32 mode
	and eax, $f		; is required to be 16 bit aligned
	add eax, edx		; add args padding and SavedRegisters[]
	sub esp, eax		; align up
				; assert(!esp & 1111b)
	; push qword(adjustment) to aligned stack
	push 0			; hidword of align size
	push eax		; align size
	; stack is not necessarily aligned, but will be after args are pushed

	mov ebp, [esp+eax+4+4+4*4+8*3]	  ; AddrLow
	mov edx, [esp+eax+4+4+4*5+8*3]	  ; AddrHigh

	mov edi, ecx		; save nArgs
	std
  @@:	lodsd			; get next arg = *(uint32_t*)args++
	push 0			; uint64_t.hi = 0
	push eax		; uint64_t.lo = arg
	sub ecx, 1
	jnz @b
  .ArgsConverted:
	push edx		; AddrHigh
	push ebp		; AddrLow
	push 0
	push edi		; num_args
	; far call pushes 2 dwords, { RetAddr, RetSegment }

	call CS_MODE_NATIVE_AMD64:HeavensGate
; HeavensGateRet
; stack check (stdcall should clear args off stack)
	; | padding
	; - - - - - - - - - - - - - - 64bit accessible
	; | QWORD SavedRegisters[3] - { rbx, rsi, rdi }
	; | QWORD cbPadding
	; V
  .Done:
	pop ecx 		; padding.lowdword
	add ecx, 8*3+4		; SavedRegisters[] and (uint64_t){ .highdword }
	add esp, ecx		; get rid of stack alignment padding

	pop esi
	pop edi
	pop ebp

	cld			; play nice with c

	ret 4*4

; PRIVATE uint32_t __stdcall xx(int nArgs, func_t Addr, ...)
; stack check:
	; padding
	; - - - - - - - - - - - - - - 64bit accessible
	;   | QWORD SavedRegisters[3] - { rbx, rsi, rdi }
	;   | QWORD cbPadding
	; 18| QWORD Args[]
	; 10| QWORD Callee
	; 8 | QWORD Num_args
	; 0 | QWORD ret addr
	;   V
align 16
HeavensGate:
  use64
	mov rax, [rsp+8]	; num_args
	; calculate SavedRegisters[] space, point to SavedRegisters[3]
	lea rcx, [rsp+rax*8+8*3+8*2]
	mov [rcx], rdi
	mov [rcx+8], rsi
	mov [rcx+8*2], rbx

	pop rsi 		; save return addr and segment
	pop rax 		; get num args
	pop rbx 		; get callee

	; setup args - first four in rcx, rdx, r8, r9 respectively, rest on stack
	test rax, rax
	jz @f
	pop rcx
	sub rax, 1
	jz @f
	pop rdx
	sub rax, 1
	jz @f
	pop r8
	sub rax, 1
	jz @f
	pop r9
	sub rax, 1
	mov rdi, rax		; preserve num_args
  @@:	call rbx
; stack check (stdcall should clear args off stack)
	; | padding
	; - - - - - - - - - - - - - - 64bit accessible
	; | QWORD SavedRegisters[3] - { rbx, rsi, rdi }
	; | QWORD cbPadding
	; V
	mov rcx, rsi		; return address
	; restore nonvolatile registers
	mov rdi, [rsp+8+8*0]
	mov rsi, [rsp+8+8*1]
	mov rbx, [rsp+8+8*2]

	push rcx		; reset return address and segment
use32	retf

; PRIVATE size_t __stdcall xx(__u32 uchar* DestLow, __u32 uchar* DestHigh,
;                             __u32 const uchar* Src, size_t cbSrc)
x64Write:
  use64
	mov r10, rsi
	mov r11, rdi
  ; convert struct { uint32_t lo, hi; } addr64 to void*
	mov edi, edx
	shl rdi, 32	; DestHigh
	or rdi, rcx	; DestLow

	mov rsi, r8	; Src
	mov rcx, r9	; cbDest
	mov rax, rcx	; return

	cld
	rep movsb

	sub rcx, rax	; difference written : expected

	mov rsi, r10
	mov rdi, r11
	ret

; PRIVATE size_t __stdcall xx(__64 const uchar* SrcLow, __64 const uchar* SrcHigh,
;                             __32 uchar* Dest, size_t cbDest)
x64Read:
  use64
	mov r10, rsi
	mov r11, rdi
  ; convert struct { uint32_t lo, hi; } addr64 to void*
	mov esi, edx
	shl rsi, 32	; DestHigh
	or rsi, rcx	; DestLow

	mov rdi, r8	; Dest
	mov rcx, r9	; cbDest
	mov rax, rcx	; Difference for return

	cld
	rep movsb

	sub rcx, rax	; difference read : expected

	mov rsi, r10
	mov rdi, r11
	ret