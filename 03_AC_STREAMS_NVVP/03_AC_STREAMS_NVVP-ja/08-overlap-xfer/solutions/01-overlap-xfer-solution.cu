#include <stdio.h>

__global__
void initWith(float num, float *a, int N)
{

  int index = threadIdx.x + blockIdx.x * blockDim.x;
  int stride = blockDim.x * gridDim.x;

  for(int i = index; i < N; i += stride)
  {
    a[i] = num;
  }
}

__global__
void addVectorsInto(float *result, float *a, float *b, int N)
{
  int index = threadIdx.x + blockIdx.x * blockDim.x;
  int stride = blockDim.x * gridDim.x;

  for(int i = index; i < N; i += stride)
  {
    result[i] = a[i] + b[i];
  }
}

void checkElementsAre(float target, float *vector, int N)
{
  for(int i = 0; i < N; i++)
  {
    if(vector[i] != target)
    {
      printf("FAIL: vector[%d] - %0.0f does not equal %0.0f\n", i, vector[i], target);
      exit(1);
    }
  }
  printf("Success! All values calculated correctly.\n");
}

int main()
{
  int deviceId;
  int numberOfSMs;

  cudaGetDevice(&deviceId);
  cudaDeviceGetAttribute(&numberOfSMs, cudaDevAttrMultiProcessorCount, deviceId);

  const int N = 2<<24;
  size_t size = N * sizeof(float);

  float *a;
  float *b;
  float *c;
  float *h_c;

  cudaMalloc(&a, size);
  cudaMalloc(&b, size);
  cudaMalloc(&c, size);
  cudaMallocHost(&h_c, size);

  size_t threadsPerBlock;
  size_t numberOfBlocks;

  threadsPerBlock = 256;
  numberOfBlocks = 32 * numberOfSMs;

  cudaError_t addVectorsErr;
  cudaError_t asyncErr;

  /*
   * 3 つのデータ ベクトルを並列で初期化するために、3 つのストリームを作成します。
   */

  cudaStream_t stream1, stream2, stream3;
  cudaStreamCreate(&stream1);
  cudaStreamCreate(&stream2);
  cudaStreamCreate(&stream3);

  /*
   * 各 `initWith` の起動に個別の非標準ストリームを割り当てます。
   */

  initWith<<<numberOfBlocks, threadsPerBlock, 0, stream1>>>(3, a, N);
  initWith<<<numberOfBlocks, threadsPerBlock, 0, stream2>>>(4, b, N);
  initWith<<<numberOfBlocks, threadsPerBlock, 0, stream3>>>(0, c, N);

  for (int i = 0; i < 4; ++i)
  {
    cudaStream_t stream;
    cudaStreamCreate(&stream);

    addVectorsInto<<<numberOfBlocks/4, threadsPerBlock, 0, stream>>>(&c[i*N/4], &a[i*N/4], &b[i*N/4], N/4);
    cudaMemcpyAsync(&h_c[i*N/4], &c[i*N/4], size/4, cudaMemcpyDeviceToHost, stream);
    cudaStreamDestroy(stream);
  }

  addVectorsErr = cudaGetLastError();
  if(addVectorsErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(addVectorsErr));

  asyncErr = cudaDeviceSynchronize();
  if(asyncErr != cudaSuccess) printf("Error: %s\n", cudaGetErrorString(asyncErr));

  checkElementsAre(7, h_c, N);

  /*
   * ストリームが不要になったら、ストリームを破棄します。
   */

  cudaStreamDestroy(stream1);
  cudaStreamDestroy(stream2);
  cudaStreamDestroy(stream3);

  cudaFree(a);
  cudaFree(b);
  cudaFree(c);
  cudaFreeHost(h_c);
}
