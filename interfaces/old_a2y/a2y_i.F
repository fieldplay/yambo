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
integer function a2y_i(np,pid,lnstr,iinf,iind,iod,icd,ijs,instr,inf,ind,od,com_dir,js)
 !
 use pars,                ONLY:SP,lchlen
 use LOGO,                ONLY:pickup_a_random
 use com,                 ONLY:msg,write_to_report,core_io_path,write_the_logo,&
&                              com_path
 use stderr,              ONLY:log_as_a_file,write_to_log,logfile,intc
 use LIVE_t,              ONLY:live_timing_is_on
 use parallel_m,          ONLY:ncpu,myid
 use electrons,           ONLY:levels,E_reset,n_sp_pol,n_spinor
 use D_lattice,           ONLY:n_atoms_species_max
 use R_lattice,           ONLY:bz_samp,bz_samp_reset,nkibz
 use wave_func,           ONLY:wf_ncx,io_WF,wf_nb_io_groups,wf_nb_io
 use IO_m,                ONLY:io_control,OP_WR_CL,NONE,OP_APP_CL,serial_number,mk_dir
 use interfaces,          ONLY:PARALLEL_live_message
 use mod_com2y,           ONLY:interface_presets,force_noWFs
 use mod_wf2y,            ONLY:WF_splitter
 use pseudo,              ONLY:PP_free
 !
#include<memory.h>
 !
 type(levels)                 :: en 
 type(bz_samp)                :: k 
 integer,          intent(in) :: lnstr,iind,iod,ijs,np,pid,icd
 integer,          intent(in) :: iinf
 character(lnstr), intent(in) :: instr
 character(iinf),  intent(in) :: inf
 character(iind),  intent(in) :: ind
 character(iod),   intent(in) :: od
 character(ijs),   intent(in) :: js
 character(icd),   intent(in) :: com_dir   
 !
 character(lchlen) :: KSS_file_name
 integer           :: ID,io_err,ik,ib_grp,i_sp_pol,ifrag
 integer,     external :: a2y_KSS_file_name,io_DB1,io_KB_abinit
 complex(SP), allocatable :: wf_disk(:,:,:)
 !
 ! Presets
 !
 a2y_i =0
 ncpu  =np
 myid  =pid
 call SET_defaults(instr,od,od,'')
 call SET_job_strings_and_dirs(js)
 call interface_presets(instr)
 call bz_samp_reset(k)
 call E_reset(en) 
#if defined _MEM_CHECK 
 call MEM_defaults( )
#endif
 !
 ! S/N
 !
 serial_number=pickup_a_random(10000._SP)
 !
 ! Switch off report file support
 !
 write_to_report=.FALSE.
 write_to_log      = .true.
 live_timing_is_on = .true.
 !
 if (log_as_a_file) then
   if (len_trim(com_path)==0) com_path="./"
   write (logfile,'(2a)') trim(com_path),'/l-e2y'
   !
   if (ncpu>1) then
     call mk_dir(trim(com_path)//"/LOG")
     write (logfile,'(2a)') trim(com_path)//'/LOG/l-e2y'
     logfile=trim(logfile)//"_CPU_"//trim(intc(myid+1))
   endif
   !
 endif
 !
 ! LOGO
 !
 call write_the_logo(6,' ')
 !
 call PARALLEL_live_message('A(binit) 2 Y(ambo)')
 !
 call msg('s','Checking input file ...')
 !
 if ( a2y_KSS_file_name(inf,KSS_file_name) < 0 ) then
   call msg('ln','failed')
   return
 endif
 call msg('l',trim(KSS_file_name))
 !
 call msg('s','DBs path set to :',trim(core_io_path))
 !
 call a2y_db1(en,k,trim(KSS_file_name))
 !
 call msg('s','Writing main Database ...')
 !
 call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1,2/),ID=ID)
 io_err=io_DB1(en,k,ID)
 !
 call msg('s','... Database done')
 !
 if (force_noWFs) then
   call msg('s',' == A2Y completed ==')
   call msg('s',' ')
   return
 endif
 !
 call WF_splitter()
 !
 call msg('s','Writing WFs and (eventually) nlPP ...')
 !
 YAMBO_ALLOC(wf_disk,(wf_ncx,n_spinor,wf_nb_io))
 !
 do i_sp_pol=1,n_sp_pol
   do ik=1,nkibz
     !
     ifrag=ik+(i_sp_pol-1)*nkibz
     !
     do ib_grp=1,wf_nb_io_groups
       !
       if (ifrag==1.and.ib_grp==1) then
         if (n_atoms_species_max>0) then
           call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID)
           io_err=io_KB_abinit(ID)
         endif
         call io_control(ACTION=OP_WR_CL,COM=NONE,SEC=(/1/),ID=ID)
       endif
       !
       call a2y_wf(wf_disk,i_sp_pol,ik,ib_grp,trim(KSS_file_name))
       !
       if (n_atoms_species_max>0.and.ib_grp==1) then
         call io_control(ACTION=OP_APP_CL,COM=NONE,SEC=(/ifrag+1/),ID=ID)
         io_err=io_KB_abinit(ID)
       endif
       !
       call io_control(ACTION=OP_APP_CL,COM=NONE,SEC=(/ifrag+1,ib_grp/),ID=ID)
       io_err=io_WF(ID,wf_disk)
       !
     enddo
     !
  enddo
 enddo
 !
 YAMBO_FREE(wf_disk)
 !
 call PP_free()
 !
#if defined _MEM_CHECK 
 !
 ! Memory Overview
 !=================
 call MEM_report("final")
 !
#endif
 !
 call msg('s','... WF and PP done')
 call msg('s',' == A2Y completed ==')
 call msg('s',' ')
 !
end function
