!
!        Copyright (C) 2000-2019 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM
! 
! This file is distributed under the terms of the GNU 
! General Public License. You can redistribute it and/or 
! modify it under the terms of the GNU General Public 
! License as published by the Free Software Foundation; 
! either version 2, or (at your option) any later version.
!
! This program is distributed in the hope that it will 
! be useful, but WITHOUT ANY WARRANTY; without even the 
! implied warranty of MERCHANTABILITY or FITNESS FOR A 
! PARTICULAR PURPOSE.  See the GNU General Public License 
! for more details.
!
! You should have received a copy of the GNU General Public 
! License along with this program; if not, write to the Free 
! Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
! MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.
!
! Analogously to io_DIPOLES, we write the io files of BS with the
! information of the q-vector
! Just to use what is done:
! BS_Q_##_
!
integer function io_BS(iq,X,ID)
 !
 use pars,          ONLY:SP,schlen,lchlen
 use X_m,           ONLY:X_t
 use stderr,        ONLY:intc
 use parallel_m,    ONLY:myid
 use pointers,      ONLY:linkM2V
 use BS,            ONLY:BS_blk,n_BS_blks,BS_K_has_been_calculated_loaded,BS_K_coupling
 use BS_solvers,    ONLY:BSS_description,BSS_n_descs,variables_BS
 use IO_m,          ONLY:io_connect,io_disconnect,io_sec,io_elemental,&
&                        def_variable_bulk,io_variable_bulk,frag_BS_K,&
&                        write_is_on,io_header,io_mode,VERIFY, &
&                        io_fragment,IO_NOT_ALLOWED,io_BS_K,manage_OP_IF_START_and_CL_IF_END
 use timing_m,      ONLY:timing
 !
#include<memory.h>
 !
 type(X_t):: X 
 integer  :: iq,ID
 !
 ! Work Space
 !
 complex(SP),pointer ::tmp_link(:)
 integer             ::i_block,i1,n1,n2,block_pos,VAR_ID,n_blocks
 character(schlen)   ::ch,db_name,PARALLEL_STRUCTURE
 character(lchlen)   ::local_description(100)
 !
 if (.not.io_BS_K.and.maxval(io_sec(ID,:))>1) then
   io_BS=IO_NOT_ALLOWED
   call io_disconnect(ID,FORCE=.TRUE.)
   return
 endif
 !
 call timing('io_BS',OPR='start')
 !
 db_name='BS_Q'//trim(intc(iq))//'_CPU_'//trim(intc(myid))
 !
 io_BS=io_connect(desc=trim(db_name),type=2,ID=ID)
 if (io_BS/=0) goto 1
 !
 if (any((/io_sec(ID,:)==1/))) then
   !
   PARALLEL_STRUCTURE="NONE"
   if (io_mode(ID)==VERIFY.or.write_is_on(ID)) PARALLEL_STRUCTURE="Response_T_space"
   !
   io_BS=io_header(ID,QPTS=.true.,R_LATT=.true.,WF=.true.,IMPOSE_SN=.true.,XC_KIND="K_WF force Xs",&
&                    PARALLEL_STRUCTURE=trim(PARALLEL_STRUCTURE),CUTOFF=.true.,FRAG=frag_BS_K)
   !
   if (io_BS/=0) then
     call io_elemental(ID,VAR="",VAR_SZ=0,MENU=1)
     goto 1
   endif
   !
   io_BS=variables_BS(ID,iq,local_description,.TRUE.,X=X)
   !
   if (io_BS/=0) then
     !
     ! reset the descriptions...
     !
     BSS_n_descs=0
     !
     goto 1
     !
   endif
   !
   ! Descriptions transfer
   !
   if (BSS_n_descs==0) then
     do i1=1,100
       if (len_trim(local_description(i1))>0) then
         BSS_n_descs=BSS_n_descs+1
         BSS_description(BSS_n_descs)=local_description(i1)
       endif
     enddo
   endif
   !
 endif
 !
 i_block=maxval(io_sec(ID,:))-1
 !
 if (i_block==0) goto 1
 !
 call manage_OP_IF_START_and_CL_IF_END(ID,NOW=i_block,LAST=n_BS_blks)
 !
 call io_fragment(ID,i_fragment=i_block)
 !
 if (BS_blk(i_block)%mode=="R") ch="BSE_RESONANT"
 if (BS_blk(i_block)%mode=="C") ch="BSE_COUPLING"
 if (BS_blk(i_block)%mode=="A") ch="BSE_ANTI-RESONANT"
 if (BS_blk(i_block)%mode=="Q") ch="BSE_ANTI-COUPLING"
 !
 if(frag_BS_K) then
   ch=trim(ch)//"_BLOCK_"//trim(intc(i_block))
   call def_variable_bulk(ID,trim(ch),1,(/2,BS_blk(i_block)%size(1),BS_blk(i_block)%size(2)/),SP)
   call io_variable_bulk(ID,1,C2=BS_blk(i_block)%mat)
 else
   if (.not.BS_K_coupling           ) n_blocks=1
   if (     BS_K_coupling.and. iq==1) n_blocks=2
   if (     BS_K_coupling.and. iq/=1) n_blocks=4
   if (BS_blk(i_block)%mode=="R") VAR_ID=1
   if (BS_blk(i_block)%mode=="C") VAR_ID=2
   if (BS_blk(i_block)%mode=="A") VAR_ID=3
   if (BS_blk(i_block)%mode=="Q") VAR_ID=4
   if(i_block<=n_blocks) call def_variable_bulk(ID,trim(ch),VAR_ID,(/2,sum(BS_blk(:)%size(1)*BS_blk(:)%size(2))/),SP)
   n1=BS_blk(i_block)%size(1)
   n2=BS_blk(i_block)%size(2)
   block_pos=sum(BS_blk(:i_block-1)%size(1)*BS_blk(:i_block-1)%size(2))+1
   tmp_link => linkM2V(BS_blk(i_block)%mat,(/n1*n2/))
   call io_variable_bulk(ID,VAR_ID,C1=tmp_link,IPOS=(/1,block_pos/))
   nullify(tmp_link)
 endif
 !
1 continue
 !
 ! If the database is not ok but the BS_identifier has been read I may have problems
 ! with the inversion database (like dimensions errors).
 !
 if (io_BS==0) BS_K_has_been_calculated_loaded=.TRUE.
 if (io_BS< 0) BS_K_has_been_calculated_loaded=.FALSE.
 !
 call io_disconnect(ID)
 !
 call timing('io_BS',OPR='stop')
 !
end function
