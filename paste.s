* paste - concatinate file in parallel
*
* Itagaki Fumihiko 24-Apr-94  Create.
* 1.0
*
* Usage: paste [ -sBCZ ] [ -d <デリミタ・リスト> ] [ -- ] [ <ファイル> ] ...
*

.include doscall.h
.include chrcode.h

.xref DecodeHUPAIR
.xref issjis
.xref strlen
.xref strcmp
.xref strfor1
.xref strip_excessive_slashes
.xref mulul
.xref divul

STACKSIZE	equ	2048

INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED	equ	8192
OUTBUF_SIZE	equ	8192
BLOCKSIZE	equ	1024

BUFSIZE		equ	8192

CTRLD	equ	$04
CTRLZ	equ	$1A

FLAG_s		equ	0
FLAG_B		equ	1
FLAG_C		equ	2
FLAG_Z		equ	3
FLAG_somedone	equ	4

.offset 0
fd_fileno:	ds.l	1
fd_buff_ptr:	ds.l	1
fd_buff_remain:	ds.l	1
fd_name:	ds.l	1
fd_link:	ds.l	1
fd_ctrlz:	ds.b	1
fd_ctrld:	ds.b	1
fd_last:	ds.b	1
fd_eof:		ds.b	1
fd_size:


.text

start:
		bra.s	start1
		dc.b	'#HUPAIR',0
start1:
		lea	bss_top(pc),a6
		lea	stack_bottom(a6),a7
		lea	$10(a0),a0			*  A0 : PDBアドレス
		move.l	a7,d0
		sub.l	a0,d0
		move.l	d0,-(a7)
		move.l	a0,-(a7)
		DOS	_SETBLOCK
		addq.l	#8,a7
	*
		move.l	#-1,stdin(a6)
	*
	*  引数並び格納エリアを確保する
	*
		lea	1(a2),a0			*  A0 := コマンドラインの文字列の先頭アドレス
		bsr	strlen				*  D0.L := コマンドラインの文字列の長さ
		addq.l	#1,d0
		bsr	malloc
		bmi	insufficient_memory

		movea.l	d0,a1				*  A1 := 引数並び格納エリアの先頭アドレス
	*
	*  引数をデコードし，解釈する
	*
		moveq	#0,d6				*  D6.W : エラー・コード
		bsr	DecodeHUPAIR			*  引数をデコードする
		movea.l	a1,a0				*  A0 : 引数ポインタ
		move.l	d0,d7				*  D7.L : 引数カウンタ
		subq.l	#1,d0
		bne	decode_opt_start

		lea	word_board(pc),a1
		bsr	strcmp
		beq	pasteboard
decode_opt_start:
		moveq	#0,d5				*  D5.L : フラグ
		lea	default_dlist(pc),a2
		move.l	a2,dlist(a6)
decode_opt_loop1:
		tst.l	d7
		beq	decode_opt_done

		cmpi.b	#'-',(a0)
		bne	decode_opt_done

		tst.b	1(a0)
		beq	decode_opt_done

		subq.l	#1,d7
		addq.l	#1,a0
		move.b	(a0)+,d0
		cmp.b	#'-',d0
		bne	decode_opt_loop2

		tst.b	(a0)+
		beq	decode_opt_done

		subq.l	#1,a0
decode_opt_loop2:
		moveq	#FLAG_s,d1
		cmp.b	#'s',d0
		beq	set_option

		cmp.b	#'d',d0
		beq	set_dlist

		cmp.b	#'B',d0
		beq	option_B_found

		cmp.b	#'C',d0
		beq	option_C_found

		moveq	#FLAG_Z,d1
		cmp.b	#'Z',d0
		beq	set_option

		moveq	#1,d1
		tst.b	(a0)
		beq	bad_option_1

		bsr	issjis
		bne	bad_option_1

		moveq	#2,d1
bad_option_1:
		move.l	d1,-(a7)
		pea	-1(a0)
		move.w	#2,-(a7)
		lea	msg_illegal_option(pc),a0
		bsr	werror_myname_and_msg
		DOS	_WRITE
		lea	10(a7),a7
usage:
		lea	msg_usage(pc),a0
		bsr	werror
		moveq	#1,d6
		bra	exit_program

needs_dlist:
		lea	msg_needs_dlist(pc),a0
		bsr	werror_myname_and_msg
		bra	usage

set_dlist:
		tst.b	(a0)
		bne	set_dlist_1

		subq.l	#1,d7
		bcs	needs_dlist

		addq.l	#1,a0
set_dlist_1:
		move.l	a0,dlist(a6)
		bsr	strfor1
		bra	decode_opt_loop1

option_B_found:
		bclr	#FLAG_C,d5
		bset	#FLAG_B,d5
		bra	set_option_done

option_C_found:
		bclr	#FLAG_B,d5
		bset	#FLAG_C,d5
		bra	set_option_done

set_option:
		bset	d1,d5
set_option_done:
		move.b	(a0)+,d0
		bne	decode_opt_loop2
		bra	decode_opt_loop1

decode_opt_done:
	*
	*  compile dlist
	*
		movea.l	dlist(a6),a1
		movea.l	a1,a2
compile_dlist_loop:
		move.b	(a2)+,d0
		beq	compile_dlist_done

		cmp.b	#'\',d0
		bne	compile_dlist_store_1

		move.b	(a2)+,d0
		beq	compile_dlist_done

		move.b	d0,d1
		moveq	#0,d0
		cmp.b	#'0',d1
		beq	compile_dlist_store_1

		moveq	#HT,d0
		cmp.b	#'t',d1
		beq	compile_dlist_store_1

		moveq	#LF,d0
		cmp.b	#'n',d1
		beq	compile_dlist_store_1

		moveq	#CR,d0
		cmp.b	#'r',d1
		beq	compile_dlist_store_1

		moveq	#FS,d0
		cmp.b	#'f',d1
		beq	compile_dlist_store_1

		moveq	#VT,d0
		cmp.b	#'v',d1
		beq	compile_dlist_store_1

		moveq	#BS,d0
		cmp.b	#'b',d1
		beq	compile_dlist_store_1

		move.b	d1,d0
compile_dlist_store_1:
		move.b	d0,(a1)+
		bsr	issjis
		bne	compile_dlist_loop

		move.b	(a2)+,d0
		move.b	d0,(a1)+
		bne	compile_dlist_loop
compile_dlist_done:
		move.l	a1,dlist_bottom(a6)
	*
	*  標準入力を切り替える
	*
		clr.w	-(a7)				*  標準入力を
		DOS	_DUP				*  複製したハンドルから入力し，
		addq.l	#2,a7
		move.l	d0,stdin(a6)
		bmi	stdin_ok

		clr.w	-(a7)
		DOS	_CLOSE				*  標準入力はクローズする．
		addq.l	#2,a7				*  こうしないと ^C や ^S が効かない
stdin_ok:
		btst	#FLAG_s,d5
		bne	paste_serial
****************
**  parallel
**
		*
		*  入力デスクリプタテーブルを確保する
		*
		moveq	#-1,d2
		moveq	#0,d4				*  D4.L <- オープンしたファイル数
		move.l	d7,d0				*  D7.L : 入力ファイル数
		bne	paste_parallel_1

		lea	static_fd(a6),a2
		move.l	a2,inputs(a6)
		lea	default_filearg(pc),a0
		moveq	#1,d7
		bra	paste_parallel_2

paste_parallel_1:
		moveq	#fd_size,d1
		bsr	mulul
		tst.l	d1
		bne	insufficient_memory

		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,inputs(a6)
		movea.l	d0,a2
		*
		*  すべての入力ファイルをオープンする
		*
paste_parallel_2:
		move.l	d7,num_files(a6)
		move.l	d7,d1
paste_parallel_open_files_loop:
		bsr	open_arg
		bmi	exit_program

		movea.l	a2,a3
		lea	fd_size(a2),a2
		subq.l	#1,d1
		bne	paste_parallel_open_files_loop

		st	fd_last(a3)
		move.l	d4,num_opened(a6)
		bsr	alloc_buffer			*  バッファを確保する
		bsr	paste				*  実行
		bra	all_done			*  終了
****************
**  serial
**
paste_serial:
		*  バッファを確保
		moveq	#1,d4
		move.l	d4,num_files(a6)
		bsr	alloc_buffer			*  バッファを確保する

		tst.l	d7				*  D7.L : 入力ファイル数
		bne	paste_serial_1

		lea	default_filearg(pc),a0
		moveq	#1,d7
paste_serial_1:
paste_serial_loop:
		lea	static_fd(a6),a2
		move.l	a2,inputs(a6)
		moveq	#-1,d2
		bsr	open_arg			*  ファイルをオープンする
		bmi	paste_serial_next

		sf	fd_last(a2)
		moveq	#1,d0
		move.l	d0,num_opened(a6)
		clr.b	lastchar(a6)
		sf	cr_saved(a6)
		bsr	paste				*  実行
		move.b	lastchar(a6),d0
		move.b	cr_saved(a6),d2
		bsr	put_last_newline
paste_serial_next:
		subq.l	#1,d7
		bne	paste_serial_loop
****************
all_done:
		bsr	flush_outbuf
exit_program:
		move.l	stdin(a6),d0
		bmi	exit_program_1

		clr.w	-(a7)				*  標準入力を
		move.w	d0,-(a7)			*  元に
		DOS	_DUP2				*  戻す．
		DOS	_CLOSE				*  複製はクローズする．
exit_program_1:
		move.w	d6,-(a7)
		DOS	_EXIT2

pasteboard:
		pea	msg_board(pc)
		DOS	_PRINT
		addq.l	#4,a7
		bra	exit_program_1
****************************************************************
open_arg:
		movea.l	a0,a1
		bsr	strfor1
		exg	a0,a1
		cmpi.b	#'-',(a0)
		bne	open_arg_file

		tst.b	1(a0)
		bne	open_arg_file

		tst.l	d2
		bmi	open_arg_1st_stdin

		move.l	d2,fd_link(a2)
		bra	open_arg_done

open_arg_1st_stdin:
		move.l	a2,d2
		lea	msg_stdin(pc),a0
		move.l	stdin(a6),d0
		bra	open_arg_1

open_arg_file:
		bsr	strip_excessive_slashes
		clr.w	-(a7)
		move.l	a0,-(a7)
		DOS	_OPEN
		addq.l	#6,a7
open_arg_1:
		tst.l	d0
		bmi	open_arg_failure

		move.l	d0,fd_fileno(a2)
		sf	fd_eof(a2)
		move.l	#-1,fd_link(a2)
		btst	#FLAG_Z,d5
		sne	fd_ctrlz(a2)
		sf	fd_ctrld(a2)
		bsr	check_device
		bmi	open_arg_2

		btst	#7,d0				*  '0':block  '1':character
		beq	open_arg_2

		btst	#5,d0				*  '0':cooked  '1':raw
		bne	open_arg_2

		st	fd_ctrlz(a2)
		st	fd_ctrld(a2)
open_arg_2:
		move.l	a0,fd_name(a2)
		clr.l	fd_buff_remain(a2)
		addq.l	#1,d4
open_arg_done:
		moveq	#0,d0
open_arg_return:
		sf	fd_last(a2)
		movea.l	a1,a0
		tst.l	d0
		rts

open_arg_failure:
		bsr	werror_myname_and_msg
		lea	msg_open_fail(pc),a0
		bsr	werror
		moveq	#2,d6
		moveq	#-1,d0
		bra	open_arg_return
****************************************************************
* paste
*
* CALL
*      none
*
* RETURN
*      D0-D4/A1-A4   破壊
****************************************************************
paste:
paste_loop1:
		clr.l	num_saved_delimiter(a6)
		bclr	#FLAG_somedone,d5
		movea.l	dlist(a6),a2
		move.l	a2,dlistP(a6)
paste_loop2:
		movea.l	inpbuf_top(a6),a3		*  A3 : この入力ファイル用のバッファの先頭アドレス
		movea.l	inputs(a6),a4			*  A4 : fdポインタ
		move.l	num_files(a6),d4		*  D4.L : loop counter
paste_loop3:
		movea.l	a4,a2
		move.l	fd_link(a2),d0
		bmi	DoOne_1

		movea.l	d0,a2
DoOne_1:
		sf	d2				*  D2.B : CR ペンディング・フラグ
		sf	d3				*  D3.B : 1文字でも入力があったかどうか
		moveq	#0,d0
		tst.l	fd_fileno(a2)
		bmi	DoOne_eof

		movea.l	fd_buff_ptr(a2),a1		*  A1 : bufferポインタ
		move.l	fd_buff_remain(a2),d1		*  D1.L : buffer data remain
DoOne_loop1:
		tst.l	d1
		bne	DoOne_2

		tst.b	fd_eof(a2)
		bne	DoOne_eof_detected

		movea.l	a3,a1
		move.l	inpbuf_size(a6),-(a7)
		move.l	a1,-(a7)
		move.l	fd_fileno(a2),d0
		move.w	d0,-(a7)
		DOS	_READ
		lea	10(a7),a7
		move.l	d0,d1
		bmi	read_fail

		tst.b	fd_ctrlz(a2)
		beq	trunc_ctrlz_done

		moveq	#CTRLZ,d0
		bsr	trunc
trunc_ctrlz_done:
		tst.b	fd_ctrld(a2)
		beq	trunc_ctrld_done

		moveq	#CTRLD,d0
		bsr	trunc
trunc_ctrld_done:
		tst.l	d1
		bne	DoOne_2
DoOne_eof_detected:
		bsr	flush_saved_cr
		subq.l	#1,num_opened(a6)
		move.l	fd_fileno(a2),d0
		move.l	#-1,fd_fileno(a2)
		cmp.l	stdin(a6),d0
		beq	DoOne_eof

		move.w	d0,-(a7)
		DOS	_CLOSE
		addq.l	#2,a7
DoOne_eof:
		moveq	#0,d0
		bra	DoOne_done

DoOne_2:
		bsr	flush_saved_delimiter
		st	d3
		subq.l	#1,d1
		move.b	(a1)+,d0
		cmp.b	#LF,d0
		beq	DoOne_done_more

		bsr	flush_saved_cr
		cmp.b	#CR,d0
		beq	DoOne_cr

		bsr	putc
		bra	DoOne_loop1

DoOne_cr:
		st	d2
		bra	DoOne_loop1

DoOne_done_more:
		move.l	a1,fd_buff_ptr(a2)
		move.l	d1,fd_buff_remain(a2)
DoOne_done:
		tst.b	fd_last(a4)
		bne	DoOne_done_last

		addq.l	#1,num_saved_delimiter(a6)
		tst.b	d3
		beq	DoOne_return

		bset	#FLAG_somedone,d5
		move.b	d0,lastchar(a6)
		move.b	d2,cr_saved(a6)
		bra	DoOne_return

DoOne_done_last:
		tst.b	d3
		bne	DoOne_done_last_1

		btst	#FLAG_somedone,d5
		beq	DoOne_return			*  すべてcloseした -> 終了

		bsr	flush_saved_delimiter
DoOne_done_last_1:
		bsr	put_last_newline
DoOne_return:
		lea	fd_size(a4),a4
		adda.l	inpbuf_size(a6),a3
		subq.l	#1,d4
		bne	paste_loop3

		tst.l	num_opened(a6)
		beq	paste_done

		btst	#FLAG_s,d5
		bne	paste_loop2
		bra	paste_loop1

paste_done:
		rts
*****************************************************************
trunc:
		movem.l	d2/a2,-(a7)
		move.l	d1,d2
		beq	trunc_done

		movea.l	a1,a2
trunc_find_loop:
		cmp.b	(a2)+,d0
		beq	trunc_found

		subq.l	#1,d2
		bne	trunc_find_loop
		bra	trunc_done

trunc_found:
		subq.l	#1,a2
		move.l	a2,d1
		sub.l	a1,d1
		st	fd_eof(a2)			*  EOF detected
trunc_done:
		movem.l	(a7)+,d2/a2
		rts
*****************************************************************
read_fail:
		lea	fd_name(a2),a0
		bsr	werror_myname_and_msg
		lea	msg_read_fail(pc),a0
		bra	werror_exit_3
****************************************************************
flush_saved_delimiter:
		move.l	num_saved_delimiter(a6),d0
		beq	flush_saved_delimiter_return
flush_saved_delimiter_loop:
		bsr	put_delimiter
		subq.l	#1,d0
		bne	flush_saved_delimiter_loop

		clr.l	num_saved_delimiter(a6)
flush_saved_delimiter_return:
		rts
****************************************************************
put_delimiter:
		movem.l	d0/a0,-(a7)
		movea.l	dlistP(a6),a0
		cmpa.l	dlist_bottom(a6),a0
		bne	put_delimiter_1

		movea.l	dlist(a6),a0
		cmpa.l	dlist_bottom(a6),a0
		beq	put_delimiter_return
put_delimiter_1:
		move.b	(a0)+,d0
		beq	put_delimiter_done

		cmp.b	#LF,d0
		bne	put_delimiter_2

		moveq	#CR,d0
		bsr	putc
		moveq	#LF,d0
		bra	put_delimiter_3

put_delimiter_2:
		bsr	putc
		bsr	issjis
		bne	put_delimiter_done

		move.b	(a0)+,d0
put_delimiter_3:
		bsr	putc
put_delimiter_done:
		move.l	a0,dlistP(a6)
put_delimiter_return:
		movem.l	(a7)+,d0/a0
		rts
****************************************************************
flush_saved_cr:
		tst.b	d2
		beq	flush_saved_cr_return

		move.l	d0,-(a7)
		moveq	#CR,d0
		bsr	putc
		move.l	(a7)+,d0
		sf	d2
flush_saved_cr_return:
		rts
****************************************************************
put_last_newline:
		tst.b	d0
		beq	put_last_newline_1		*  改行が無かったならばCR+LFを出力

		btst	#FLAG_C,d5
		beq	put_last_newline_2
put_last_newline_1:
		st	d2
put_last_newline_2:
		bsr	flush_saved_cr
		moveq	#LF,d0
****************************************************************
putc:
		movem.l	d0/a0,-(a7)
		tst.b	do_buffering(a6)
		bne	putc_buffering

		move.w	d0,-(a7)
		move.l	#1,-(a7)
		pea	5(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	12(a7),a7
		cmp.l	#1,d0
		bne	write_fail
		beq	putc_done

putc_buffering:
		tst.l	outbuf_free(a6)
		bne	putc_buffering_1

		bsr	flush_outbuf
putc_buffering_1:
		movea.l	outbuf_ptr(a6),a0
		move.b	d0,(a0)+
		move.l	a0,outbuf_ptr(a6)
		subq.l	#1,outbuf_free(a6)
putc_done:
		movem.l	(a7)+,d0/a0
		rts
*****************************************************************
flush_outbuf:
		move.l	d0,-(a7)
		tst.b	do_buffering(a6)
		beq	flush_outbuf_return

		move.l	#OUTBUF_SIZE,d0
		sub.l	outbuf_free(a6),d0
		beq	flush_outbuf_return

		move.l	d0,-(a7)
		move.l	outbuf_top(a6),-(a7)
		move.w	#1,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		tst.l	d0
		bmi	write_fail

		cmp.l	-4(a7),d0
		blo	write_fail

		move.l	outbuf_top(a6),d0
		move.l	d0,outbuf_ptr(a6)
		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
flush_outbuf_return:
		move.l	(a7)+,d0
		rts
*****************************************************************
write_fail:
		lea	msg_write_fail(pc),a0
		bra	werror_exit_3
*****************************************************************
* alloc_buffer
*
* CALL
*      D4.L   入力ファイル数
*
* RETURN
*      D0-D2   破壊
*****************************************************************
alloc_buffer:
		moveq	#1,d0				*  出力は
		bsr	is_chrdev			*  キャラクタ・デバイスか？
		seq	do_buffering(a6)
		beq	input_max			*  -- block device

		*  character device
		btst	#5,d0				*  '0':cooked  '1':raw
		bne	input_max

		*  cooked character device
		btst	#FLAG_B,d5
		bne	input_step_by_step

		bset	#FLAG_C,d5			*  改行を変換する
input_step_by_step:
		move.l	#INPBUF_SIZE_MAX_TO_OUTPUT_TO_COOKED,d0
		move.l	d0,inpbuf_size(a6)
		move.l	d4,d1
		bsr	mulul
		tst.l	d1
		beq	inpbufsize_ok
input_max:
		move.l	#$00ffffff,d0
		move.l	d0,inpbuf_size(a6)
inpbufsize_ok:
		move.l	d0,d2				*  D2.L : inpbuf_size * ファイル数
		*  出力バッファを確保する
		tst.b	do_buffering(a6)
		beq	outbuf_ok

		move.l	#OUTBUF_SIZE,d0
		move.l	d0,outbuf_free(a6)
		bsr	malloc
		bmi	insufficient_memory

		move.l	d0,outbuf_top(a6)
		move.l	d0,outbuf_ptr(a6)
outbuf_ok:
		move.l	d2,d0
		bsr	malloc
		bpl	inpbuf_ok

		sub.l	#$81000000,d0
		move.l	d0,d2				*  D2.L : 確保可能最大ブロックのサイズ
		move.l	d4,d1				*  それをファイル数で
		bsr	divul				*  割る
		move.l	d0,inpbuf_size(a6)
		beq	insufficient_memory		*  0 ならばエラー
		*
		*  可能ならば inpbuf_size を BLOCKSIZE の整数倍とする
		*
		move.l	#BLOCKSIZE,d1
		cmp.l	d1,d0
		bls	do_alloc_inpbuf

		bsr	divul
		move.l	inpbuf_size(a6),d0
		sub.l	d1,d0
		move.l	d0,inpbuf_size(a6)
		move.l	d4,d1
		bsr	mulul
		move.l	d0,d2
do_alloc_inpbuf:
		move.l	d2,d0
		bsr	malloc
		bmi	insufficient_memory
inpbuf_ok:
		move.l	d0,inpbuf_top(a6)
		rts
*****************************************************************
insufficient_memory:
		bsr	werror_myname
		lea	msg_no_memory(pc),a0
werror_exit_3:
		bsr	werror
		moveq	#3,d6
		bra	exit_program
*****************************************************************
werror_myname:
		move.l	a0,-(a7)
		lea	msg_myname(pc),a0
		bsr	werror
		movea.l	(a7)+,a0
		rts
*****************************************************************
werror_myname_and_msg:
		bsr	werror_myname
werror:
		movem.l	d0/a1,-(a7)
		movea.l	a0,a1
werror_1:
		tst.b	(a1)+
		bne	werror_1

		subq.l	#1,a1
		suba.l	a0,a1
		move.l	a1,-(a7)
		move.l	a0,-(a7)
		move.w	#2,-(a7)
		DOS	_WRITE
		lea	10(a7),a7
		movem.l	(a7)+,d0/a1
		rts
*****************************************************************
is_chrdev:
		bsr	check_device
		bpl	is_chrdev_1

		moveq	#0,d0
is_chrdev_1:
		btst	#7,d0
		rts
*****************************************************************
check_device:
		move.w	d0,-(a7)
		clr.w	-(a7)
		DOS	_IOCTRL
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
malloc:
		move.l	d0,-(a7)
		DOS	_MALLOC
		addq.l	#4,a7
		tst.l	d0
		rts
*****************************************************************
.data

	dc.b	0
	dc.b	'## paste 1.0 ##  Copyright(C)1994 by Itagaki Fumihiko',0

msg_myname:		dc.b	'paste: ',0
word_board:		dc.b	'-board',0
msg_no_memory:		dc.b	'メモリが足りません',CR,LF,0
msg_open_fail:		dc.b	': オープンできません',CR,LF,0
msg_read_fail:		dc.b	': 入力エラー',CR,LF,0
msg_write_fail:		dc.b	'paste: 出力エラー',CR,LF,0
msg_stdin:		dc.b	'- 標準入力 -',0
msg_illegal_option:	dc.b	'不正なオプション -- ',0
msg_needs_dlist:	dc.b	'-d には <デリミタ・リスト> 引数が必要です',0
msg_usage:		dc.b	CR,LF,'使用法:  paste [-sBCZ] [-d <デリミタ・リスト>] [--] [<ファイル>] ...',CR,LF,0
msg_board:	dc.b	'pasteboard n. 1 厚紙, ボール紙. 2【俗】カード, 名刺, 切符, トランプ札など. 3 紙製の; にせの.',CR,LF,0
default_filearg:	dc.b	'-',0
default_dlist:		dc.b	HT,0
*****************************************************************
.bss
.even
bss_top:

.offset 0
static_fd:		ds.b	fd_size
.even
inpbuf_top:		ds.l	1
inpbuf_size:		ds.l	1
outbuf_top:		ds.l	1
outbuf_ptr:		ds.l	1
outbuf_free:		ds.l	1
dlist:			ds.l	1
dlistP:			ds.l	1
dlist_bottom:		ds.l	1
stdin:			ds.l	1
inputs:			ds.l	1
num_files:		ds.l	1
num_opened:		ds.l	1
num_saved_delimiter:	ds.l	1
do_buffering:		ds.b	1
cr_saved:		ds.b	1
lastchar:		ds.b	1

.even
			ds.b	STACKSIZE
.even
stack_bottom:

.bss
		ds.b	stack_bottom
*****************************************************************

.end start
