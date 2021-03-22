use std::mem::MaybeUninit;

use once_cell::sync::OnceCell;

use emacs::Env;

type AccessBufferContents = unsafe fn(*mut *const u8, *mut isize, *mut *const u8, *mut isize);

#[allow(non_upper_case_globals)]
pub static ng_module_access_current_buffer_contents: OnceCell<AccessBufferContents> = OnceCell::new();

pub unsafe fn current_buffer_contents(_: &Env) -> (&[u8], &[u8]) {
    let mut before_gap = MaybeUninit::uninit();
    let mut after_gap = MaybeUninit::uninit();
    let mut before_gap_size: isize = 0;
    let mut after_gap_size: isize = 0;
    let f = ng_module_access_current_buffer_contents.get().unwrap();
    f(
        before_gap.as_mut_ptr(),
        &mut before_gap_size,
        after_gap.as_mut_ptr(),
        &mut after_gap_size,
    );
    let before_gap_size = before_gap_size;
    let after_gap_size = after_gap_size;
    (
        if before_gap_size > 0 {
            std::slice::from_raw_parts(
                before_gap.assume_init() as *const u8,
                before_gap_size as usize,
            )
        } else {
            &[]
        },
        if after_gap_size > 0 {
            std::slice::from_raw_parts(
                after_gap.assume_init() as *const u8,
                after_gap_size as usize,
            )
        } else {
            &[]
        },
    )
}
