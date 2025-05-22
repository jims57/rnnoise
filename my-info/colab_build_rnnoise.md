# Check available source files
%cd /content/rnnoise
!ls -la src/

# Compile all available C files in the src directory
!mkdir -p build
%cd build
!gcc -c -I.. -I../include -I../src ../src/*.c

# Create a static library
!ar rcs librnnoise.a *.o

# Compile the demo with our new library
%cd /content/rnnoise/examples
!gcc -o rnnoise_demo rnnoise_demo.c -I../include -L../build -lrnnoise -lm

# If compilation works, run the demo
!./rnnoise_demo noisy_speech.pcm denoised_speech.pcm