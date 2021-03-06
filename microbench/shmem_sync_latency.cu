/****
 * Copyright (c) 2014, NVIDIA Corporation.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *    * Redistributions of source code must retain the above copyright notice,
 *      this list of conditions and the following disclaimer.
 *    * Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *    * Neither the name of the NVIDIA Corporation nor the names of its
 *      contributors may be used to endorse or promote products derived from
 *      this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 ****/

#include <stdio.h>
#include <assert.h>
#include <cuda.h>
#include <cuda_runtime.h>
#include "nvshmem.h"
#include "nvshmem_device.h"
#include "mpi.h"

#define CUDA_CHECK(stmt)                                \
do {                                                    \
    cudaError_t result = (stmt);                        \
    if (cudaSuccess != result) {                        \
        fprintf(stderr, "[%s:%d] cuda failed with %s \n",   \
         __FILE__, __LINE__,cudaGetErrorString(result));\
        exit(-1);                                       \
    }                                                   \
    assert(cudaSuccess == result);                      \
} while (0)

__global__ void ping_pong (int *wait_flag_d, int pe, int iter, int skip) {
    long long int start, stop, time; 
    int i, peer;
 
    peer = !pe;   

    for (i=0; i<(iter+skip); i++) {
       if (i == skip) start = clock(); 
 
       //printf("pe: %d peer: %d cond: %d \n", pe, peer, i&1);

       if ((i&1) == pe) { 
            nvshmem_int_wait_until (wait_flag_d, 0, i+1);

	    nvshmem_int_p (wait_flag_d, i+1, peer);
            nvshmem_quiet ();   
       } else {
	    nvshmem_int_p (wait_flag_d, i+1, peer);
            nvshmem_quiet ();    

            nvshmem_int_wait_until (wait_flag_d, 0, i+1);
       }
    }
    stop = clock();

    if (pe == 0) { 
        time = (stop - start)/iter;
        printf("sync latency: %lld cycles\n", time);
    }
}

int main (int c, char *v[])
{
    int local_rank = 0;
    int dev_count, mype, npes; 
    int *wait_flag_d; 

    int iter = 200; 
    int skip = 20;

    CUDA_CHECK(cudaGetDeviceCount(&dev_count));
    if (dev_count <= 0) {
        fprintf(stderr, "no CUDA devices found \n");
        exit(-1);
    }

    if (getenv("MV2_COMM_WORLD_LOCAL_RANK") != NULL) { 
        local_rank = atoi(getenv("MV2_COMM_WORLD_LOCAL_RANK"));   
    }
    CUDA_CHECK(cudaSetDevice(local_rank%dev_count));

    MPI_Init (&c, &v);
    nvstart_pes();
    mype = nvshmem_my_pe();
    npes = nvshmem_n_pes();

    if (npes != 2) { 
        fprintf(stderr, "This test requires exactly two processes \n");
        goto finalize;
    }
 
    wait_flag_d = (int *) nvshmalloc (sizeof(int)); 
    cudaMemset(wait_flag_d, 0, sizeof(int));
    CUDA_CHECK(cudaDeviceSynchronize());

    ping_pong <<<1, 1>>> (wait_flag_d, mype, iter, skip);  

    CUDA_CHECK(cudaDeviceSynchronize());

    nvshmem_barrier_all();

finalize:

    nvshmcleanup();

    nvstop_pes();
    MPI_Finalize();

    return 0;
}
