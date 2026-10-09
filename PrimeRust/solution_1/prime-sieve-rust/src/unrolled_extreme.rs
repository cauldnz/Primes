use helper_macros::{extreme_reset, generic_dispatch};

use crate::{
    primes::FlagStorage,
    unrolled::{patterns::pattern_equivalent_skip, ResetterSparseU8},
};

/// Storage structure implementing standard linear bit storage, but with a hybrid bit setting strategy:
/// - dense resetting for small skip factors
/// - sparse resetting for larger skip factors
/// This algorithm is functionally equivalent to [`crate::unrolled::FlagStorageUnrolledHybrid`], but we use a procedural
/// macro to write the dense reset functions instead of relying on the compiler to do so implicitly via const-generics.
/// Performance, as a result, is very similar. This method has a slight edge over the const-generics, and is
/// primarily included to demonstrate how this approach can be used in Rust.
pub struct FlagStorageExtremeHybrid {
    lines: Box<[CacheLine]>,
    num_words: usize,
    length_bits: usize,
}

/// Eight words on a 64-byte boundary: the flag words start on a cache line.
#[repr(C, align(64))]
#[derive(Clone, Copy)]
struct CacheLine([u64; 8]);

impl FlagStorageExtremeHybrid {
    #[inline(always)]
    fn words(&self) -> &[u64] {
        // Safety: `lines` holds at least `num_words` contiguous u64s.
        unsafe { std::slice::from_raw_parts(self.lines.as_ptr() as *const u64, self.num_words) }
    }

    #[inline(always)]
    fn words_mut(&mut self) -> &mut [u64] {
        // Safety: as above, and we hold the only reference.
        unsafe { std::slice::from_raw_parts_mut(self.lines.as_mut_ptr() as *mut u64, self.num_words) }
    }
}

impl FlagStorage for FlagStorageExtremeHybrid {
    fn create_true(size: usize) -> Self {
        let num_words = size / 64 + (size % 64).min(1);
        Self {
            lines: vec![CacheLine([0; 8]); (num_words + 7) / 8].into_boxed_slice(),
            num_words,
            length_bits: size,
        }
    }

    /// As with [`crate::unrolled::FlagStorageUnrolledHybrid`], this method dispatches
    /// to a dense "extreme" resetter for skip factors below <= 129, and otherwise calls the same
    /// sparse resetter for higher skip factors. The only difference is that we use
    /// the "extreme" dense resetter: [`helper_macros::extreme_reset`]
    #[inline(always)]
    fn reset_flags(&mut self, skip: usize) {
        // sparse resets for skip factors larger than those covered by dense resets
        if skip > 129 {
            let equivalent_skip = pattern_equivalent_skip(skip, 8);
            generic_dispatch!(
                equivalent_skip,
                3,
                2,
                17,
                ResetterSparseU8::<N>::reset_sparse(self.words_mut(), skip),
                debug_assert!(
                    false,
                    "this case should not occur skip {} equivalent {}",
                    skip, equivalent_skip
                )
            );
            return;
        }

        // dense resets for all odd numbers in {3, 5, ... =129}
        let words = self.words_mut();
        extreme_reset!(skip);
    }

    #[inline(always)]
    fn get(&self, index: usize) -> bool {
        if index >= self.length_bits {
            return false;
        }
        let word = self.words().get(index / 64).unwrap();
        *word & (1 << (index % 64)) == 0
    }
}
