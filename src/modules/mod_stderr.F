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
module stderr
 !
 use pars
 !
 implicit none
 !
 integer          :: tty_size
 logical          :: write_to_log
 logical          :: write_to_log_default
 logical          :: write_fragments_IO_log
 logical          :: log_as_a_file
 character(lchlen):: logfile
 !
 integer :: f_format_length
 integer :: g_format_length
 integer :: of_tabs(30)
 !
 ! Slash
 !
#if defined _aix || defined _XLF || defined _PGI
 character(2), parameter :: slash="\\"
#else 
 character(1), parameter :: slash="\"
#endif
 !
 interface  
   !
   subroutine win_size(wdim)
     integer :: wdim
   end subroutine
   !
   subroutine c_fprintf(lfmt,msg,rfmt,sfmt)
     character(*) :: lfmt,rfmt,msg,sfmt
   end subroutine
   !
 end interface
 !
 contains
   !
   subroutine set_real_printed_length(f_length,g_length)
     integer, optional :: f_length,g_length
     integer           :: it
     if (present(f_length)) then
       f_format_length=f_length
     endif
     if (present(g_length)) then
       g_format_length=g_length
     endif
     if (.not.present(f_length).and..not.present(g_length)) then
       f_format_length=9
       g_format_length=9
     endif
     !
     of_tabs(1)=4
     do it=2,30
       of_tabs(it)=of_tabs(it-1)+4+max(f_format_length,g_format_length)
     enddo
   end subroutine
   !
   subroutine c_print(lfmt,msg,rfmt,sfmt)
     character(*) :: lfmt,rfmt,msg,sfmt
     call c_fprintf(cstr(lfmt),cstr(msg),cstr(rfmt),cstr(sfmt))
   end subroutine
   !
   subroutine remove_new_line(s)
    character(len=*) :: s
    integer          :: i
    do i = 1, len(s)
      if (s(i:i) .eq. achar(10)) then
        s(i:i)= " "
      end if
    end do
  end subroutine
   !
   character(lchlen) function cstr(si) result(so)
     character(*), intent(IN) :: si
     integer :: i 
     i = len(trim(si))
     call clear_str(so)
     so(1:i) = si(1:i)
     so(i+1:i+1) = achar(0)
   end function cstr
   !
   subroutine clear_str(str)
     character(*), intent(out) :: str
     integer :: i
     do i = 1, len(str)
       str(i:i) = " " 
     end do
   end subroutine clear_str
   !
   character(lchlen) function STRING_pack(str1,str2,str3,str4,str5)
     character(*)          :: str1
     character(*),optional :: str2,str3,str4,str5
     !
     ! Work Space
     !
     character(lchlen) :: lch
     !
     STRING_pack=str1
     if (present(str2)) then
       write (lch,'(2a)') trim(STRING_pack),trim(str2)
       STRING_pack=lch
     endif
     if (present(str3)) then
       write (lch,'(2a)') trim(STRING_pack),trim(str3)
       STRING_pack=lch
     endif
     if (present(str4)) then
       write (lch,'(2a)') trim(STRING_pack),trim(str4)
       STRING_pack=lch
     endif
     if (present(str5)) then
       write (lch,'(2a)') trim(STRING_pack),trim(str5)
       STRING_pack=lch
     endif
   end function 
   !
   subroutine STRING_split(string_in,string_out,space,n_non_empty_strings)
     character(*)          :: string_in
     character(schlen)     :: string_out(:)
     character(*),optional :: space
     integer,     optional :: n_non_empty_strings
     !
     ! Work Space
     !
     integer          :: i_pos(2),is
     character(1)     :: space_
     !
     space_=" "
     if (present(space)) space_=space(1:1)
     !
     i_pos=(/1,1/)
     is=0
     string_out=""
     do while (i_pos(1)<=len_trim(string_in))
       !
       ! Here I go to the first non null characater " AB  C"
       !                                              |
       do while (string_in(i_pos(1):i_pos(1)) == space_)
         if (i_pos(1)==len_trim(string_in)) exit
         i_pos(1)=i_pos(1)+1
       enddo
       !
       ! Here I go to the last non-null characater before a space " AB  C"
       !                                                             |   
       i_pos(2)=i_pos(1)
       do while (string_in(i_pos(2):i_pos(2)) /= space_)
         if (i_pos(2)==len_trim(string_in)) exit
         i_pos(2)=i_pos(2)+1
       enddo
       if(i_pos(2)<len_trim(string_in)) i_pos(2)=i_pos(2)-1
       ! 
       is=is+1
       string_out(is)=trim(string_in(i_pos(1):i_pos(2)))
       i_pos(1)=i_pos(2)+1
       !
       if (i_pos(2)==len_trim(string_in)) exit
       !
     enddo
     !
     if (present(n_non_empty_strings)) then
       n_non_empty_strings=0
       do is=1,size(string_out)
         if (len_trim(string_out(is))>0) n_non_empty_strings=n_non_empty_strings+1
       enddo
     endif
     !
   end subroutine
   !
   character(lchlen) function STRING_remove(string_in,what,replace)
     !
     character(*)           :: string_in
     character(*)           :: what
     character(*), optional :: replace
     !
     ! Work Space
     !
     integer          :: i_pos,i_s
     character(lchlen):: string_tmp
     !
     STRING_remove=string_in
     !
     i_pos=index(string_in,what)
     !
     if (i_pos==0) return
     !
     string_tmp=string_in
     !
     do i_s=1,len_trim(string_in)
       if (present(replace)) then
         STRING_remove=string_tmp(:i_pos-1)//replace//string_tmp(i_pos+len(what):)
       else
         STRING_remove=string_tmp(:i_pos-1)//string_tmp(i_pos+len(what):)
       endif
       string_tmp=STRING_remove
       i_pos=index(string_tmp,what)
       if (i_pos==0) return
     enddo
     !
   end function
   !
   character(lchlen) function STRING_add(string_in,what)
     !
     character(*)     :: string_in
     character(*)     :: what
     !
     ! Work Space
     !
     integer          :: i_pos
     !
     STRING_add=string_in
     i_pos=index(string_in,what)
     if (i_pos/=0) return
     write (STRING_add,'(2a)') trim(string_in),trim(what)
     !
   end function
   !
   character(8) function intc(i)
     !
     character(8) temp
     integer, intent(in) :: i
     !
     if(i.lt.10.and.i.ge.0) then
       write(temp,'(i1)') i
     else if(i.lt.100.and.i.gt.-10) then
       write(temp,'(i2)') i
     else if(i.lt.1000.and.i.gt.-100) then
       write(temp,'(i3)') i
     else if(i.lt.10000.and.i.gt.-1000) then
       write(temp,'(i4)') i
     else if(i.lt.100000.and.i.gt.-10000) then
       write(temp,'(i5)') i
     else if(i.lt.1000000.and.i.gt.-100000) then
       write(temp,'(i6)') i
     else if(i.lt.10000000.and.i.gt.-1000000) then
       write(temp,'(i7)') i
     else if(i.lt.100000000.and.i.gt.-10000000) then
       write(temp,'(i8)') i
     else
       write(temp,'(a6)') "******"
     endif
     intc = temp
     !
   end function intc
   !
   character(3) function log2ch(i)
     !
     logical, intent(in) :: i
     !
     log2ch='no '
     if (i) log2ch='yes'
     !
   end function log2ch
   !
   character(schlen) function real2ch(r)
     !
     real(SP), intent(in) :: r
     character(schlen)    :: fmt_
     !
     fmt_=gen_fmt(r_v=(/r/))
     write(real2ch,'('//trim(fmt_)//')') r
     !
   end function real2ch
   !
   character(schlen) function complex2ch(c)
     !
     complex(SP), intent(in) :: c
     real(SP)                :: r(2)
     character(schlen)       :: fmt_(2)
     !
     r(1)=real(c)
     r(2)=aimag(c)
     fmt_(1)=gen_fmt(r_v=(/r(1)/))
     fmt_(2)=gen_fmt(r_v=(/r(2)/))
     write(complex2ch,'('//trim(fmt_(1))//','//trim(fmt_(2))//')') r
     !
   end function complex2ch
   !
   character(schlen) function gen_fmt(i_v,r_v)
     integer ,optional :: i_v(:)
     real(SP),optional :: r_v(:)
     !
     ! Work Space
     !
     integer  :: MXexp,MNexp,MDexp,iexp,MXval,i1
     real(SP) :: MX,MN,abs_r_v
     !
     if (present(i_v)) then
       MXval=max(maxval(i_v),-minval(i_v))
       iexp=1
       if (MXval/=0) iexp=nint(log10(real(MXval)))+2
       write (gen_fmt,'(a,i2.2)')  'i',iexp
     endif
     !
     if (present(r_v)) then
       MN= huge(SP)
       MX=-huge(SP)
       do i1=1,size(r_v)
         abs_r_v=abs(r_v(i1))
         if (abs_r_v<MN.and.abs_r_v>0._SP) MN=abs_r_v
         if (abs_r_v>MX.and.abs_r_v>0._SP) MX=abs_r_v
       enddo
       MXexp=int(log10(MX))
       MNexp=int(log10(MN))
       iexp=max(iabs(MXexp),iabs(MNexp))
       MDexp=int(log10(MX/MN))
       if (size(r_v)==1.and.r_v(1)==0.) then
         iexp=0
         MDexp=0
       endif
       !
       if (iexp<=2.and.MDexp<=2) then
         !
         !  f_format_length-3-iexp:  3 for '-','.' + 1 as iexp(10)=1/iexp(100)=2
         !
         write (gen_fmt,'(2(a,i2.2))')  'F',f_format_length,'.',f_format_length-3-iexp
         !
       else
         !
         ! 23/9/2011. Field intensities formats are wrong when iexp=9. This is beacause
         ! depending on the compiler 1.E9 is written  as 0.1E10. Therefore I need to uses
         ! a reference iexp=8 to distinguish the two possible formats.
         !
         if (iexp< 9) write (gen_fmt,'(2(a,i2.2),a)')  'G',g_format_length,'.',g_format_length-5,'E1'
         !
         !  g_format_length-6: 6 because of '-1.','E00'
         !
         if (iexp> 8) write (gen_fmt,'(2(a,i2.2),a)')  'G',g_format_length,'.',g_format_length-6,''
         !
       endif
       !
     endif
     !
  end function
  !
  subroutine STRING_to_LOWER(strIn)
    character(len=*), intent(inout) :: strIn
    integer :: i,j
    do i = 1, len(strIn)
      j = iachar(strIn(i:i))
      if (j>= iachar("A") .and. j<=iachar("Z") ) j=j+32
      strIn(i:i) = achar(j)
    enddo
  end subroutine
  !
  subroutine STRING_to_UPPER(strIn)
    character(len=*), intent(inout) :: strIn
    integer :: i,j
    do i = 1, len(strIn)
      j = iachar(strIn(i:i))
      if (j>= iachar("a") .and. j<=iachar("z") ) j=j-32
      strIn(i:i) = achar(j)
    enddo
  end subroutine
  !
  logical function STRING_match(strIn,MATCH)
    !
    ! Adapted from http://www.star.le.ac.uk/~cgp/fortran.html (25 May 2012)
    ! Original author: Clive Page
    !
    character(len=*), intent(in) :: strIn
    character(len=*), intent(in) :: MATCH
    !
    character(len=len(strIn)) :: str_
    character(len=len(MATCH)) :: MATCH_
    integer :: i,j
    !
    STRING_match=.FALSE.
    !
    if (len(strIn)/=len(MATCH)) return
    !
    do i = 1, len(strIn)
      !
      j = iachar(strIn(i:i))
      if (j>= iachar("a") .and. j<=iachar("z") ) j=j-32
      str_(i:i) = achar(j)
      !
      j = iachar(MATCH(i:i))
      if (j>= iachar("a") .and. j<=iachar("z") ) j=j-32
      MATCH_(i:i) = achar(j)
      !
    end do
    !
    STRING_match=trim(str_)==trim(MATCH_)
    !
  end function STRING_match
  !
end module stderr
