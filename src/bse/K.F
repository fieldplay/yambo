!
!        Copyright (C) 2000-2019 the YAMBO team
!              http://www.yambo-code.org
!
! Authors (see AUTHORS file for details): AM DS AF
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
subroutine K(iq,Ken,Xk,q,X,Xw,W_bss)
 !
 ! K = <2V-W> for n_spin=1
 !
 use pars,         ONLY:IP,SP,schlen,pi,cZERO,cI
 use stderr,       ONLY:intc
 use LOGO,         ONLY:pickup_a_random
 use drivers,      ONLY:l_bs_fxc,l_bss
 use frequency,    ONLY:w_samp
 use electrons,    ONLY:levels,spin_occ,spin,n_spin,E_SOC_nbands
 use FFT_m,        ONLY:fft_size
 use interfaces,   ONLY:WF_load,WF_free
 use functions,    ONLY:K_scatter
 use D_lattice,    ONLY:nsym,DL_vol,i_time_rev,sop_tab,sop_inv,i_space_inv
 use R_lattice,    ONLY:G_m_G,qindx_B,bz_samp,qindx_X
 use com,          ONLY:warning,error,msg
 use stderr,       ONLY:intc
 use LIVE_t,       ONLY:live_timing
 use X_m,          ONLY:X_t
 use BS_solvers,   ONLY:BSS_q0
 use BS,           ONLY:BS_bands,BS_res_K_corr,BS_W,BS_W_is_diagonal,&
&                       BS_res_K_exchange,BS_Block_size,&
&                       O_ng,BS_n_g_exch,BS_identifier,BS_LiveTiming_steps,&
&                       BS_K_dim,BS_K_is_ALDA,BS_cpl_K_exchange,&
&                       BS_cpl_K_corr,K_EXCH_collision,K_CORR_collision,&
&                       BS_oscillators_free,WF_phase,n_BS_blks,BS_blk,BS_T_grp,&
&                       BS_K_has_been_calculated_loaded,BS_nT_grps,BS_blks_free,&
&                       l_BSE_minimize_memory, l_restart_bse
 use collision_el, ONLY:elemental_collision_free
 use IO_m,         ONLY:io_control,OP_RD_CL,REP,VERIFY,NONE,OP_RD,&
&                       RD,WR,RD_CL,RD_CL_IF_END,OP_WR_CL,WR_CL,OP_WR,OP_APP_CL,DUMP,&
&                       deliver_IO_error_message
 use TDDFT,         ONLY:FXC_K_diagonal,FXC,FXC_n_g_corr,io_BS_Fxc
 use xc_functionals,ONLY:F_xc,XC_potential_driver
 use global_XC,     ONLY:WF_kind,WF_xc_functional
 use wave_func,     ONLY:WF
 use openmp,        ONLY:OPENMP_update,master_thread
 use timing_m,      ONLY:timing
 !
#if defined _KERR
 use KERR,           ONLY:BSS_KERR_free
#endif
 !
#include<memory.h>
#include<yambo_bse.h>
 !
 type(levels)  ::Ken 
 type(bz_samp) ::Xk,q
 type(X_t)     ::X
 type(w_samp)  ::Xw,W_bss
 integer       ::iq
 !
 ! Work Space ...
 !
 character(schlen) :: section_title
 !
 ! ... Kernel loop
 !
 DEFINE_BSK_COMMON_INDEXES
 integer    :: i_block,O_ng_shift,&
&              ig_kmq,ig_pmq,ig_W_mq,iq_W_bz_mq,iq_W_mq,iq_W_s_mq,&
&              bands_to_load(2),is_k(4),os_k(4),is_p(4),os_p(4)
 complex(SP):: Co,H_x,H_c
 real(SP)   :: sqrt_f_itk,sqrt_f_itp
 !
 complex(SP),   external ::TDDFT_ALDA_R_space
 complex(SP),   external ::K_correlation_kernel
 complex(SP),   external ::K_exchange_kernel_resonant,K_exchange_kernel_coupling
 !
 ! Oscillators
 !
 logical    :: load_O_X
 !
 ! I/O
 !
 integer           ::io_X_err,io_BS_Fxc_err,io_BS_err,ID
 integer, external ::io_BS
 !
 ! Constants & Setup
 !==================
 !
 if(E_SOC_nbands==0) Co=4._SP*real(spin_occ)*pi/DL_vol/real(q%nbz,SP)
 if(E_SOC_nbands/=0) Co=4._SP               *pi/DL_vol/real(q%nbz,SP)
 io_BS_err    =-1
 io_BS_Fxc_err=-1
 !
 call elemental_collision_free(K_CORR_collision)
 call elemental_collision_free(K_EXCH_collision)
 !
 ! K/S Table
 !
 call k_build_up_BZ_tables(Xk)
 !
 call timing('X T_space Kernel',OPR='start')
 !
 ! Titles
 !========
 !
 if (l_bs_fxc) then
   section_title="BSE Kernel -> xc-kernel"
 else
   if (BS_K_is_ALDA) then
     section_title="TDDFT Kernel"
   else
     section_title="BSE Kernel"
   endif
   section_title=trim(section_title)//" @q"//trim(intc(iq))
   !
   if (BS_res_K_corr.or.BS_res_K_exchange)     section_title=trim(section_title)//" (Resonant"
   if (BS_res_K_corr.or.BS_K_is_ALDA)          section_title=trim(section_title)//" CORRRELATION"
   if (BS_res_K_exchange)                      section_title=trim(section_title)//" EXCHANGE"
   if (BS_res_K_corr.or.BS_res_K_exchange)     section_title=trim(section_title)//")"
   !
   if (BS_cpl_K_corr.or.BS_cpl_K_exchange)     section_title=trim(section_title)//" (Coupling"
   if (BS_cpl_K_corr.or.(BS_K_is_ALDA.and.BS_cpl_K_exchange))&
&                                              section_title=trim(section_title)//" CORRRELATION"
   if (BS_cpl_K_exchange)                      section_title=trim(section_title)//" EXCHANGE"
   if (BS_cpl_K_corr.or.BS_cpl_K_exchange)     section_title=trim(section_title)//")"
   !
 endif
 !
 call section('=',trim(section_title))
 !
 ! Exchange
 !==========
 !
 load_O_X=BS_res_K_exchange.or.l_bs_fxc
 !
 if (load_O_X) call msg('r','[BSE] Exchange components :',BS_n_g_exch)
 !
 ! Oscillators Setup
 !===================
 O_ng=1
 O_ng_shift=maxval(qindx_X(iq,:,2))
 !
 if (any((/BS_res_K_corr,BS_cpl_K_corr/)).and..not.l_bs_fxc) then
   O_ng=maxval(G_m_G)
   call fft_check_size(1,O_ng,BS_n_g_exch,"Kx")
   if(iq/=1) O_ng_shift=max(maxval(qindx_B(:,:,2)),O_ng_shift)
 endif
 !
   !
#if defined _PAR_IO
   !
   ! TO DO
   !
#else
   call io_control(ACTION=OP_RD_CL,COM=REP,MODE=VERIFY,SEC=(/1/),ID=ID)
   io_BS_err=io_BS(iq,X,ID)
   !
   if (io_BS_err==0.and.l_bss) then
     call io_control(ACTION=OP_RD,COM=NONE,MODE=DUMP,SEC=(/1/),ID=ID)
     io_BS_err=io_BS(iq,X,ID)
     do i_block=1,n_BS_blks
       call io_control(ACTION=RD_CL_IF_END,COM=NONE,MODE=DUMP,SEC=(/i_block+1/),ID=ID)
       io_BS_err=io_BS(iq,X,ID)
     enddo
   endif
#endif
   !
   if (io_BS_err==0) goto 1
   !
 !
 ! Screened interaction
 !======================
 io_X_err=0
 if (BS_res_K_corr) call K_screened_interaction(X,Xw,q,io_X_err)
 !
 if (io_X_err<0) then
   call deliver_IO_error_message(io_X_err,'PP/Em1s')
   call warning('Bethe Salpter section skipped. Impossible to build the kernel.')
   n_BS_blks=0
   call BS_blks_free()
   !
#if defined _KERR
   call BSS_KERR_free( )
#endif
   !
   goto  1
   !
 endif
 !
 !
 ! Wave Functions
 !================
 bands_to_load=BS_bands
 if (BS_K_is_ALDA) bands_to_load=(/1,BS_bands(2)/)
 !
 section_title='-BSK'
 !
 call WF_load(WF,max(O_ng,BS_n_g_exch),O_ng_shift,bands_to_load,(/1,Xk%nibz/),space='R',title=trim(section_title))
 !
 ! Wave Functions Phases
 !=======================
 call K_WF_phases(Xk)
 ! 
 ! Spatial Inversion Test
 !========================
 call WF_spatial_inversion(Ken,Xk)
 !
 ! ALDA
 !======
 if (BS_K_is_ALDA) then
   YAMBO_ALLOC(F_xc,(fft_size,n_spin,n_spin))
   call XC_potential_driver(Ken,Xk,WF_KIND,WF_xc_functional,2)
 endif
 !
 ! DB identifier 
 !===============
 BS_identifier=pickup_a_random(10000._SP)
 !
 ! BS DB description section I/O
 !===============================
 !
#if defined _PAR_IO
 call io_control(ACTION=OP_RD_CL,ID=ID)
 call io_BS_PAR_check(iq,ID)
 !
 call io_control(ACTION=OP_APP_CL,COM=REP,ID=ID)
 call io_BS_PAR_init(iq,X,ID)
#else
 call io_control(ACTION=OP_WR_CL,COM=REP,SEC=(/1/),ID=ID)
 io_BS_err=io_BS(iq,X,ID)
#endif
 !
 ! Timing
 !========
 !
 if (BS_LiveTiming_steps>0) then
   if (.not.l_bs_fxc) call live_timing('Kernel',     BS_LiveTiming_steps)
   if (     l_bs_fxc) call live_timing('Kernel->Fxc',BS_LiveTiming_steps)
 endif
 !
 !------------------
 ! LOOP over blocks
 !------------------
 !
 block_loop:&
 do i_block=1,n_BS_blks
   !
   ! Read BS_blk to check if the transition was already computed
   !
#ifdef _PAR_IO
   if (l_restart_bse) then
     call io_control(ACTION=RD_CL,ID=ID)
     call io_BS_PAR_block(iq,i_block,ID)
     if (all(BS_blk(i_block)%done=="t")) cycle
   endif
#endif
   !
   i_Tgrp_k=BS_blk(i_block)%iT_k
   i_Tgrp_p=BS_blk(i_block)%iT_p
   i_k     =BS_blk(i_block)%ik
   i_p     =BS_blk(i_block)%ip
   !
   ! Exchange oscillators
   !----------------------
   ! 
   call K_exchange_collisions(iq,Xk,i_Tgrp_k)
   !
   if (i_Tgrp_k/=i_Tgrp_p) call K_exchange_collisions(iq,Xk,i_Tgrp_p)
   !
   ! Exchange oscillators
   !----------------------
   ! 
   call K_correlation_collisions(iq,i_block,Xk,q)
   !
   ! Transition Loops
   !------------------
   !
#if defined _OPENMP && ! defined _CUDA
   !$omp parallel default(shared), &
   !$omp private(i_Tk,i_Tp, &
   !$omp &       sqrt_f_itk,i_k_bz,i_v_k,i_c_k,i_k_sp_pol,i_k_s,is_k,os_k,i_k_s_m1,H_pos, &
   !$omp &       sqrt_f_itp,i_p_bz,i_v_p,i_c_p,i_p_sp_pol,i_p_s,is_p,os_p,i_kp_s, &
   !$omp &       i_kmq_bz,ig_kmq,i_kmq,i_kmq_s,i_kmq_t,i_kmq_s_m1,i_kp_mq_s, &
   !$omp &       i_pmq_bz,ig_pmq,i_pmq,i_pmq_s,i_pmq_t, &
   !$omp &       ig_W,iq_W,iq_W_s,iq_W_bz,iq_W_bz_mq,ig_W_mq,iq_W_mq,iq_W_s_mq,H_x,H_c)
#endif
   !
   call OPENMP_update(master_thread)   
   !
#if defined _OPENMP && ! defined _CUDA
   !$omp do collapse(2), schedule(dynamic)
#endif
   do i_Tp=1,BS_T_grp(i_Tgrp_p)%size
     do i_Tk=1,BS_T_grp(i_Tgrp_k)%size
       !
       ! skip this block if already done
       !
       if (BS_blk(i_block)%done(i_Tk,i_Tp)=="t") cycle
       !
       FILL_BSK_COMMON_INDEXES
       FILL_BSK_KERNEL_INDEXES
       !
       if (BS_res_K_corr.or.BS_cpl_K_corr) then 
         !
         if (iq_W_bz/=iq_W_bz_mq.or.iq_W/=iq_W_mq.or.iq_W_s/=iq_W_s_mq) call error("Wrong transferred momentum")
         !
         if ( (.not.BS_W_is_diagonal) .and. iq_W_s>nsym/(i_time_rev+1) .and. i_space_inv == 0 ) iq_W=q%nibz+iq_W
         !
       endif
       !
       H_x=cZERO
       H_c=cZERO
       !
       select case (BS_blk(i_block)%mode)
       !
       case ("R")
         !
         ! :::RESONANT TERM:::
         !=============================
         !
         ! Exchange
         if (BS_res_K_exchange) H_x=K_exchange_kernel_resonant(iq, BS_n_g_exch,               &
                                   &    BS_T_grp(i_Tgrp_p),i_Tp, BS_T_grp(i_Tgrp_k),i_Tk)
         !
         ! ALDA
         if (BS_K_is_ALDA)      H_x=H_x+TDDFT_ALDA_R_space(is_k,os_k,is_p,os_p,'RES')
         !
         ! Correlations
         if (BS_res_K_corr)     H_c=K_correlation_kernel(i_block,i_p,i_pmq, &
&                                 i_k_s,i_kp_s,i_c_k,i_c_p,i_kmq_s,i_kp_mq_s,i_v_k,i_v_p,     &
&                                 i_kmq_t,i_pmq_t,i_k_sp_pol,i_p_sp_pol,                      &
&                                 iq_W,iq_W_s,ig_W,i_k_s_m1,iq_W_s_mq,ig_W_mq,i_kmq_s_m1)
         !         
       case ("C")
         !
         ! :::COUPLING TERM:::
         !=============================
         !
         ! STILL TO FIX AT FINITE Q
         !
         ! Exchange
         if (BS_cpl_K_exchange) H_x=K_exchange_kernel_coupling(iq, BS_n_g_exch,              &
                                   &    BS_T_grp(i_Tgrp_p),i_Tp, BS_T_grp(i_Tgrp_k),i_Tk) 
         !
         ! ALDA
         if (BS_K_is_ALDA)      H_x=H_x+TDDFT_ALDA_R_space(is_k,os_k,is_p,os_p,'CPL')
         !
         ! Correlations
         if (BS_cpl_K_corr)     H_c=K_correlation_kernel(i_block,i_p,i_pmq, &
&                                 i_k_s,i_kp_s,i_c_k,i_v_p,i_kmq_s,i_kp_mq_s,i_v_k,i_c_p,    &
&                                 i_kmq_t,i_pmq_t,i_k_sp_pol,i_p_sp_pol,                     &
&                                 iq_W,iq_W_s,ig_W,i_k_s_m1,iq_W_s_mq,ig_W_mq,i_kmq_s_m1)
         !
       case ("A")
         !
         ! :::ANTI-RESONANT TERM:::
         !=============================
         !
         ! STILL TO CODE AT FINITE Q
         !
         ! Exchange
         if (BS_cpl_K_exchange) H_x=cZERO
         !
         ! ALDA
         if (BS_K_is_ALDA)      H_x=H_x
         !
         ! Correlations
         if (BS_cpl_K_corr)     H_c=cZERO
         !
       case ("Q")
         !
         ! :::ANTI-COUPLING TERM:::
         !=============================
         !
         ! STILL TO CODE AT FINITE Q
         !
         ! Exchange
         if (BS_cpl_K_exchange) H_x=cZERO
         !
         ! ALDA
         if (BS_K_is_ALDA)      H_x=H_x
         !
         ! Correlations
         if (BS_cpl_K_corr)     H_c=cZERO
         !
       end select
       !
       ! We have to add a new mode in addition to resonant and coupling for finiteq,
       ! where the kernel is recomputed in the antiresonant case
       !
       sqrt_f_itk=sqrt(BS_T_grp(i_Tgrp_k)%f(i_Tk))
       sqrt_f_itp=sqrt(BS_T_grp(i_Tgrp_p)%f(i_Tp))
       !
       if (BS_blk(i_block)%mode=="R") BS_blk(i_block)%mat(i_Tk,i_Tp)=    sqrt_f_itk*(H_x*Co-H_c)*sqrt_f_itp
       if (BS_blk(i_block)%mode=="C") BS_blk(i_block)%mat(i_Tk,i_Tp)= cI*sqrt_f_itk*(H_x*Co-H_c)*sqrt_f_itp
       if (BS_blk(i_block)%mode=="A") BS_blk(i_block)%mat(i_Tk,i_Tp)=    sqrt_f_itk*(H_x*Co-H_c)*sqrt_f_itp
       if (BS_blk(i_block)%mode=="Q") BS_blk(i_block)%mat(i_Tk,i_Tp)=-cI*sqrt_f_itk*(H_x*Co-H_c)*sqrt_f_itp
       !
       BS_blk(i_block)%done(i_Tk,i_Tp)="t"
       !
     enddo   ! i_Tk
   enddo     ! i_Tp
#if defined _OPENMP && ! defined _CUDA
   !$omp end do
   !$omp end parallel
#endif
   !
   call BS_oscillators_free(0,i_block)
   if(l_BSE_minimize_memory) then
     call BS_oscillators_free(i_Tgrp_p,0)
     call BS_oscillators_free(i_Tgrp_k,0)
   endif
   !
#if defined _PAR_IO
   call io_control(ACTION=WR_CL,ID=ID)
   call io_BS_PAR_block(iq,i_block,ID)
#else
   call io_control(ACTION=OP_APP_CL,COM=REP,SEC=(/i_block+1/),ID=ID)
   io_BS_err=io_BS(iq,X,ID)
#endif
   !
   call live_timing(steps=BS_Block_size(i_block))
   !
 enddo block_loop
 !
#if defined _PAR_IO
 call  io_BS_PAR_free(ID)
#endif
 !
 if (BS_LiveTiming_steps>0) call live_timing( )
 !
 BS_K_has_been_calculated_loaded=.TRUE.
 !
 ! GLOBAL CLEANING 
 !=================
 !
 call BS_oscillators_free(BS_nT_grps,0)
 !
 if (BS_res_K_corr.or.BS_cpl_K_corr) then
   YAMBO_FREE(WF_phase)
 endif
 !
 if (l_bs_fxc) then
   !
   !
 else if (BS_K_is_ALDA) then
   YAMBO_FREE(F_xc)
 endif
 !
1 continue
 !
 YAMBO_FREE(BS_W)
 call WF_free(WF)
 !
 call timing('X T_space Kernel',OPR='stop')
 !
end subroutine K
